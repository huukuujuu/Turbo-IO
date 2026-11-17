import Foundation
import Combine
import CryptoKit
import RayNeoArchive

struct ArchiveLibrarySnapshot: Sendable {
    let recordings: [ArchivedRecording]
    let recovery: RecoveryReport
}

enum LocalArchiveError: LocalizedError {
    case busy, fixtureUnavailable, coordinationFailed, noteMissing, noteChanged
    var errorDescription: String? {
        switch self {
        case .busy: return "보관함에서 다른 작업을 처리 중입니다. 잠시 기다리세요."
        case .fixtureUnavailable: return "합성 샘플은 개발용 테스트에만 사용합니다."
        case .coordinationFailed: return "파일 사본을 읽을 수 없습니다. 다운로드 완료 후 다시 시도하세요."
        case .noteMissing: return "Markdown 수정본을 찾을 수 없어 공유를 준비하지 못했습니다."
        case .noteChanged: return "Markdown 파일이 검증 기록과 일치하지 않아 공유를 중지했습니다. 파일을 덮어쓰지 않았습니다."
        }
    }
}

/// Only local file work. No glasses transport, microphone, ASR, network or upload implementation.
actor LocalArchiveRepository {
    private let explicitRoot: URL?
    private let limits: ArchiveLimits
    private var archive: ArchiveStore?
    private var portableExportActive = false

    init(rootDirectory: URL?, limits: ArchiveLimits = ArchiveLimits()) {
        explicitRoot = rootDirectory
        self.limits = limits
    }

    private func open() throws -> ArchiveStore {
        if let archive { return archive }
        let root: URL
        if let explicitRoot { root = explicitRoot }
        else {
            root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("VerifiedRecordingArchiveV1", isDirectory: true)
        }
        // Never point this at the old ImportedRecordings directory or a File Provider/NAS destination.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let created = try ArchiveStore(rootDirectory: root, limits: limits)
        archive = created
        return created
    }

    func load() async throws -> ArchiveLibrarySnapshot {
        let store = try open()
        let recovery = try await store.recover()
        let rows = try await store.listRecordings().sorted { $0.importedAt > $1.importedAt }
        return ArchiveLibrarySnapshot(recordings: rows, recovery: recovery)
    }

    func importFile(_ source: URL, title: String? = nil) async throws -> ArchiveReceipt {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let staging = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }
        // The coordinator accessor must remain synchronous. Materialize a bounded local copy before
        // awaiting the archive actor, keeping the source's access scope open through the entire call.
        var coordinationError: NSError?
        var copied: Result<LocalRecording, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readableURL in
            copied = Result {
                try RecordingFileImporter.copy(source: readableURL, to: staging, maximumBytes: Int(limits.maximumFileBytes))
            }
        }
        if let coordinationError { throw coordinationError }
        guard let copied else { throw LocalArchiveError.coordinationFailed }
        let localCopy = try copied.get()
        let archive = try open()
        return try await archive.importFile(at: staging.appendingPathComponent(localCopy.storedFilename),
                                            title: Self.defaultTitle(title ?? source.deletingPathExtension().lastPathComponent))
    }

    func saveTranscript(recordingID: UUID, text: String, title: String) async throws -> NoteReceipt {
        try await open().exportTranscript(for: recordingID, text: text, title: title)
    }

    func verify(_ id: UUID) async throws -> ArchiveReceipt {
        let receipt = try await open().verifyRecording(id)
        for revision in receipt.recording.transcripts {
            _ = try verifiedNoteURL(receipt: receipt, revisionID: revision.id)
        }
        return receipt
    }

    func sourceForContainerInspection(_ identity: AudioInspectionIdentity) async throws -> AudioInspectionSource {
        let receipt = try await open().verifyRecording(identity.recordingID)
        guard AudioInspectionIdentity(receipt.recording) == identity else { throw AudioContainerHostError.sourceMismatch }
        return AudioInspectionSource(identity: identity, url: receipt.audioURL)
    }

    func prepareNoteShare(recordingID: UUID, revisionID: UUID) async throws -> URL {
        let receipt = try await open().verifyRecording(recordingID)
        return try verifiedNoteURL(receipt: receipt, revisionID: revisionID)
    }

    func preparePortableShare(recordingID: UUID, revisions: SnapshotRevisionSelection) async throws -> URL {
        guard !portableExportActive else { throw LocalArchiveError.busy }
        portableExportActive = true
        defer { portableExportActive = false }
        let store = try open()
        let receipt = try await store.verifyRecording(recordingID)
        let exports = receipt.audioURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PortableArchiveExportsV1",isDirectory:true)
        try FileManager.default.createDirectory(at:exports,withIntermediateDirectories:true,
            attributes:[.posixPermissions:0o700,.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
        guard try exports.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else { throw PortableArchiveError.invalidSnapshot }
        guard try FileManager.default.contentsOfDirectory(atPath:exports.path).count < 20 else { throw PortableArchiveError.capacity }
        let parent = exports.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false,
            attributes:[.posixPermissions:0o700,.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
        let snapshot = try await store.exportSnapshot(recordingID:recordingID,revisions:revisions,toParentDirectory:parent)
        return try PortableArchiveZIP.create(snapshot)
    }

    private func exportCopies() -> PortableExportCopies {
        PortableExportCopies(parent: explicitRoot?.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    }
    func exportCopyCatalog() throws -> PortableExportCatalog {
        guard !portableExportActive else { throw LocalArchiveError.busy }
        return try exportCopies().catalog()
    }
    func moveExportCopy(_ id: UUID, toTrash: Bool) throws {
        guard !portableExportActive else { throw LocalArchiveError.busy }
        try exportCopies().move(id, toTrash: toTrash)
    }

    private func verifiedNoteURL(receipt: ArchiveReceipt, revisionID: UUID) throws -> URL {
        try Task.checkCancellation()
        guard let revision = receipt.recording.transcripts.first(where: { $0.id == revisionID }),
              let relative = receipt.recording.noteRelativePath(for: revision) else { throw LocalArchiveError.noteMissing }
        // The library has checked the pinned root location before providing this audio URL.
        let root = receipt.audioURL.deletingLastPathComponent().deletingLastPathComponent()
        let noteURL = root.appendingPathComponent(relative)
        let values = try noteURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              values.fileSize == Int(revision.byteCount), revision.byteCount <= Int64(limits.maximumTranscriptBytes) * 8 + 8_192 else {
            throw LocalArchiveError.noteChanged
        }
        let input = try FileHandle(forReadingFrom: noteURL)
        defer { try? input.close() }
        var digest = SHA256()
        var count: Int64 = 0
        while let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            count += Int64(chunk.count)
            guard count <= revision.byteCount else { throw LocalArchiveError.noteChanged }
            digest.update(data: chunk)
        }
        guard count == revision.byteCount,
              digest.finalize().map({ String(format: "%02x", $0) }).joined() == revision.noteSHA256 else { throw LocalArchiveError.noteChanged }
        return noteURL
    }

    #if DEBUG
    func importContainerFixture(_ fixture: ContainerSyntheticFixture) async throws -> ArchiveReceipt {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("synthetic-container-\(fixture.rawValue).ogg")
        try fixture.bytes().write(to: source, options: .withoutOverwriting)
        return try await importFile(source, title: fixture.title)
    }

    func importSyntheticFixture() async throws -> ArchiveReceipt {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Simulator-QA-not-valid-audio.wav")
        // Deliberately not decodable audio: the test proves copy/checksum, not recording or ASR.
        try Data(String(repeating: "SYNTHETIC BYTES; NOT VALID AUDIO.\n", count: 31).utf8).write(to: source, options: .withoutOverwriting)
        return try await importFile(source, title: "검증 테스트 샘플 · 실제 오디오 아님")
    }
    #endif

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("companion-archive-incoming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory
    }

    static func defaultTitle(_ value: String) -> String {
        let sanitized = value.components(separatedBy: .controlCharacters).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        for character in sanitized {
            guard result.utf8.count + String(character).utf8.count <= 256 else { break }
            result.append(character)
        }
        return result.isEmpty ? "로컬 녹음" : result
    }
}

@MainActor
final class LocalArchiveController: ObservableObject {
    @Published private(set) var recordings: [ArchivedRecording] = [] {
        didSet { audioInspection.reconcile(recordings: recordings, issues: verificationIssues) }
    }
    @Published private(set) var isBusy = false
    @Published private(set) var activity = ""
    @Published private(set) var exportCopies = PortableExportCatalog()
    @Published private(set) var statusMessage: String?
    @Published private(set) var latestVerifications: [UUID: Date] = [:]
    @Published private(set) var verificationIssues: [UUID: String] = [:] {
        didSet { audioInspection.reconcile(recordings: recordings, issues: verificationIssues) }
    }
    let audioInspection: AudioContainerInspectionController
    @Published var errorMessage: String?
    let allowsTestFixture: Bool
    private let repository: LocalArchiveRepository

    init(rootDirectory: URL?, allowsTestFixture: Bool = false, limits: ArchiveLimits = ArchiveLimits()) {
        let repository = LocalArchiveRepository(rootDirectory: rootDirectory, limits: limits)
        self.repository = repository
        audioInspection = AudioContainerInspectionController { identity in try await repository.sourceForContainerInspection(identity) }
        self.allowsTestFixture = allowsTestFixture
        audioInspection.onIntegrityFailure = { [weak self] identity, error in
            self?.recordContainerIntegrityFailure(identity, error: error)
        }
    }

    func load() async {
        guard !isBusy else { return }
        await perform("보관함 읽는 중…") {
            let snapshot = try await self.repository.load()
            self.recordings = snapshot.recordings
            if snapshot.recovery.recoveredTransactions > 0 || snapshot.recovery.retainedUnjournaledFiles > 0 {
                self.statusMessage = "복구됨 \(snapshot.recovery.recoveredTransactions)개 작업 · \(snapshot.recovery.retainedUnjournaledFiles)개의 미등록 임시 파일을 삭제하지 않고 유지합니다."
            }
        }
    }

    func loadExportCopies() async {
        guard !isBusy else { return }
        await perform("내보내기 사본 읽는 중…") { self.exportCopies = try await self.repository.exportCopyCatalog() }
    }
    func moveExportCopy(_ id: UUID, toTrash: Bool) async {
        guard !isBusy else { return }
        await perform("내보내기 사본 정리 중…") {
            try await self.repository.moveExportCopy(id, toTrash: toTrash)
            self.exportCopies = try await self.repository.exportCopyCatalog()
            self.statusMessage = toTrash ? "기기의 임시 보관함으로 이동했습니다. 복원 가능하며 디스크 공간은 유지됩니다." : "내보내기 사본을 복원했습니다. 다른 파일을 덮어쓰지 않았습니다."
        }
    }

    @discardableResult func importFile(_ source: URL, title: String? = nil) async -> Bool {
        var imported = false
        await perform("로컬 파일 복사 및 검증 중…") {
            self.accept(try await self.repository.importFile(source, title: title))
            self.recordings = try await self.repository.load().recordings
            imported = true
        }
        return imported
    }

    func verify(_ id: UUID) async -> URL? {
        var output: URL?
        await perform("오디오와 등록된 메모 재검증 중…", recordingID: id) {
            self.latestVerifications.removeValue(forKey: id)
            let receipt = try await self.repository.verify(id)
            self.latestVerifications[id] = receipt.verifiedAt
            self.verificationIssues.removeValue(forKey: id)
            self.statusMessage = "오디오 및 메모 바이트 검증 통과 · 디코딩, 인식 또는 업로드 없음"
            output = receipt.audioURL
        }
        return output
    }

    func saveTranscript(recordingID: UUID, text: String, title: String) async -> NoteReceipt? {
        var output: NoteReceipt?
        await perform("로컬 Markdown 수정본 저장 중…", recordingID: recordingID) {
            self.latestVerifications.removeValue(forKey: recordingID)
            let receipt = try await self.repository.saveTranscript(recordingID: recordingID, text: text, title: title)
            self.recordings = try await self.repository.load().recordings
            self.statusMessage = receipt.reusedExistingRevision
                ? "같은 텍스트와 제목이 있어 수정본 \(receipt.revision.number)을 사용합니다. 이전 원고는 유지됩니다."
                : "Markdown 수정본 \(receipt.revision.number)을 기기에 저장했습니다. 업로드하지 않았습니다."
            output = receipt
        }
        return output
    }

    func prepareNoteShare(recordingID: UUID, revisionID: UUID) async -> URL? {
        var output: URL?
        await perform("Markdown 파일 확인 중…", recordingID: recordingID) {
            self.latestVerifications.removeValue(forKey: recordingID)
            output = try await self.repository.prepareNoteShare(recordingID: recordingID, revisionID: revisionID)
        }
        return output
    }

    func preparePortableShare(recordingID: UUID, revisions: SnapshotRevisionSelection) async -> URL? {
        var output: URL?
        await perform("내보내기 사본 생성 및 ZIP 검증 중…",recordingID:recordingID) {
            self.latestVerifications.removeValue(forKey:recordingID)
            output = try await self.repository.preparePortableShare(recordingID:recordingID,revisions:revisions)
            self.statusMessage = "ZIP 검증 완료 · 오디오와 선택한 수정본이 포함됩니다. 업로드나 Obsidian 인덱싱은 확인하지 않았습니다."
        }
        return output
    }

    func importTestFixture() async {
        #if DEBUG
        guard allowsTestFixture else { errorMessage = LocalArchiveError.fixtureUnavailable.localizedDescription; return }
        await perform("테스트 샘플 가져오는 중…") {
            self.accept(try await self.repository.importSyntheticFixture())
            self.recordings = try await self.repository.load().recordings
        }
        #endif
    }

    #if DEBUG
    func importContainerFixture(_ fixture: ContainerSyntheticFixture) async {
        guard allowsTestFixture else { errorMessage = LocalArchiveError.fixtureUnavailable.localizedDescription; return }
        await perform("테스트 컨테이너 생성 및 가져오는 중…") {
            self.accept(try await self.repository.importContainerFixture(fixture))
            self.recordings = try await self.repository.load().recordings
        }
    }
    #endif

    private func accept(_ receipt: ArchiveReceipt) {
        latestVerifications[receipt.recording.id] = receipt.verifiedAt
        statusMessage = receipt.reusedExistingContent ? "같은 데이터가 있어 기존 보관 파일을 사용합니다. 원본과 기존 항목은 유지됩니다." : "로컬 사본 복사 및 검증 완료 · 디코딩, 인식, 업로드 없음"
    }

    private func recordContainerIntegrityFailure(_ identity: AudioInspectionIdentity, error: Error) {
        guard let current = recordings.first(where: { $0.id == identity.recordingID }),
              AudioInspectionIdentity(current) == identity, Self.isIntegrityFailure(error) else { return }
        latestVerifications.removeValue(forKey: identity.recordingID)
        verificationIssues[identity.recordingID] = Self.describe(error)
    }

    private func perform(_ activity: String, recordingID: UUID? = nil, operation: () async throws -> Void) async {
        guard !isBusy else { errorMessage = LocalArchiveError.busy.localizedDescription; return }
        isBusy = true; self.activity = activity; errorMessage = nil; statusMessage = nil
        defer { isBusy = false; self.activity = "" }
        do { try await operation() }
        catch {
            if let recordingID, Self.isIntegrityFailure(error) {
                verificationIssues[recordingID] = Self.describe(error)
                latestVerifications.removeValue(forKey: recordingID)
            }
            errorMessage = Self.describe(error) + "\n원본 파일을 변경하거나 삭제하지 않았습니다. 복구 기록은 다음 새로고침 때 완료될 수 있으며 실패 시 자동 롤백을 보장하지 않습니다."
        }
    }

    private static func isIntegrityFailure(_ error: Error) -> Bool {
        if let value = error as? AudioContainerHostError {
            switch value {
            case .fileChanged, .sourceMismatch, .unreadable: return true
            case .tooLarge: return false
            }
        }
        if let value = error as? ArchiveError {
            switch value {
            case .archivedContentChanged, .destinationConflict, .archiveLocationChanged, .missingRecoveryData,
                 .invalidManifest, .invalidJournal, .recordingNotFound, .io: return true
            default: return false
            }
        }
        if let value = error as? LocalArchiveError {
            switch value {
            case .noteChanged, .noteMissing: return true
            default: return false
            }
        }
        return (error as NSError).domain == NSCocoaErrorDomain
    }

    static func describe(_ error: Error) -> String {
        guard let archiveError = error as? ArchiveError else { return error.localizedDescription }
        switch archiveError {
        case .emptySource: return "선택한 파일이 비어 있습니다."
        case .fileSizeLimitExceeded: return "오디오가 보관 용량 제한(기본 512 MiB)을 초과했습니다."
        case .unsupportedFileType, .invalidFileURL: return "저장이 끝난 일반 로컬 파일을 선택하세요."
        case .sourceChangedDuringCopy: return "복사 중 원본이 변경됐습니다. 녹음 저장이 끝난 후 다시 시도하세요."
        case .invalidTitle: return "제목은 UTF-8 기준 1~256바이트의 한 줄 텍스트여야 합니다."
        case .invalidTranscript: return "텍스트를 입력하세요. 줄바꿈과 탭 이외의 제어 문자는 지원하지 않습니다."
        case .transcriptSizeLimitExceeded: return "텍스트가 1 MiB를 초과했습니다. 나눈 뒤 다시 시도하세요."
        case .recordingLimitExceeded, .revisionLimitExceeded, .manifestSizeLimitExceeded: return "보관 용량 또는 수정본 개수 한도에 도달했습니다. 원본은 유지됩니다."
        case .archivedContentChanged, .destinationConflict: return "파일과 보관 기록이 다르거나 충돌이 있어 작업을 중지했습니다. 원본은 덮어쓰지 않았습니다."
        case .archiveBusy: return "다른 작업이 보관 폴더를 사용 중입니다. 잠시 후 새로고침하세요."
        case .archiveLocationChanged: return "보관 폴더가 이동 또는 교체되어 작업을 중지했습니다. 원래 폴더를 복원한 뒤 다시 시도하세요."
        case .recordingNotFound: return "현재 보관 기록에 이 녹음이 없습니다. 새로고침하세요."
        case .invalidManifest, .invalidJournal, .missingRecoveryData: return "보관 기록이나 복구 데이터를 확인해야 합니다. 기존 파일은 유지하며 자동으로 덮어쓰지 않았습니다."
        case .invalidLimits, .targetDirectoryRequired: return "로컬 보관 폴더 또는 용량 설정이 유효하지 않습니다."
        case .io: return "파일 작업에 실패했습니다. 저장 공간, 기기 잠금 해제 및 파일 권한을 확인하세요."
        }
    }
}
