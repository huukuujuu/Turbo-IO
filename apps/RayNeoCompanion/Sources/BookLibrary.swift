import Foundation
import Combine

actor BookDiskStore {
    let root: URL
    init(root: URL) { self.root = root }
    func load() throws -> [ReadingBook] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        var result: [ReadingBook] = []
        for url in urls where url.pathExtension == "json" {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 20 * 1_024 * 1_024 else { throw BookImportError.invalid }
            let book = try JSONDecoder().decode(ReadingBook.self, from: Data(contentsOf: url))
            guard url.deletingPathExtension().lastPathComponent == book.id.uuidString,
                  !book.chapters.isEmpty, book.chapters.count <= 2_000,
                  book.chapters.enumerated().allSatisfy({ $0.offset == $0.element.id }),
                  book.chapters.reduce(0, { $0 + $1.text.utf8.count }) <= BookImporter.maximumTextBytes else { throw BookImportError.invalid }
            result.append(book)
            guard result.count <= 50 else { throw BookImportError.limit }
        }
        return result.sorted { $0.importedAt > $1.importedAt }
    }
    func save(_ book: ReadingBook) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(book)
        try data.write(to: root.appendingPathComponent(book.id.uuidString + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

@MainActor final class BookLibrary: ObservableObject {
    @Published private(set) var books: [ReadingBook] = []
    @Published private(set) var busy = false
    @Published var error: String?
    private let disk: BookDiskStore
    private var loaded = false
    let allowsTestFixture: Bool
    init(root: URL? = nil, allowsTestFixture: Bool = false) {
        self.allowsTestFixture = allowsTestFixture
        let destination = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ReadingLibraryV1")
        disk = BookDiskStore(root: destination)
    }
    func importTestFixture() async {
        #if DEBUG
        guard allowsTestFixture, !busy else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("book-fixture-\(UUID().uuidString)")
        let url = root.appendingPathComponent("자동읽기_테스트.txt")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            try Data(String(repeating: "자동 읽기 테스트 원고입니다. 드래그하면 멈추고 재생하면 현재 위치에서 이어집니다.\n\n", count: 100).utf8).write(to: url, options: .withoutOverwriting)
            await importFile(url)
        } catch { self.error = "테스트용 책을 가져오지 못했습니다." }
        #endif
    }
    func load() async {
        guard !busy, !loaded else { return }
        busy = true; defer { busy = false }
        do { books = try await disk.load(); loaded = true }
        catch { self.error = "책장을 읽지 못했습니다. 원본을 유지하며 책장을 초기화하지 않았습니다." }
    }
    func importFile(_ source: URL) async {
        guard !busy else { error = BookImportError.busy.localizedDescription; return }
        if !loaded { await load() }
        guard loaded, !busy else { return }
        guard books.count < 50 else { error = "기기 책장은 최대 50권까지 지원합니다."; return }
        busy = true; defer { busy = false }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        do {
            let book = try await Task.detached(priority: .userInitiated) { try BookImporter.read(source) }.value
            try await disk.save(book)
            books.insert(book, at: 0)
        } catch { self.error = (error as? BookImportError)?.localizedDescription ?? "책 가져오기 실패 · 파일이 기기에 다운로드됐는지 확인하세요. 원본은 변경되지 않았습니다." }
    }
    func savePosition(id: UUID, chapter: Int, progress: Double, speed: Double) async {
        guard let index = books.firstIndex(where: { $0.id == id }), books[index].chapters.indices.contains(chapter),
              progress.isFinite, speed.isFinite else { return }
        books[index].chapter = chapter; books[index].progress = min(1, max(0, progress)); books[index].speed = min(80, max(8, speed))
        let book = books[index]
        do { try await disk.save(book) } catch { self.error = "읽기 위치를 저장하지 못했습니다. 다시 시도하세요. 본문은 유지됩니다." }
    }
}

enum ReadingMotion {
    static func next(offset: Double, maximum: Double, speed: Double, elapsed: Double) -> Double {
        guard offset.isFinite, maximum.isFinite, speed.isFinite, elapsed.isFinite else { return 0 }
        // Cap a delayed frame: foreground resume must not skip entire paragraphs.
        return min(max(0, maximum), max(0, offset) + min(80, max(8, speed)) * min(0.1, max(0, elapsed)))
    }
}
