import SwiftUI
import UniformTypeIdentifiers
import UIKit
import RayNeoArchive

struct ArchiveView: View {
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var archive: LocalArchiveController
    @State private var showImporter = false
    @State private var showWorkflow = false
    @State private var filter = "전체"
    private var visibleRecordings: [ArchivedRecording] {
        archive.recordings.filter { filter == "전체" || (filter == "텍스트 대기" ? $0.transcripts.isEmpty : !$0.transcripts.isEmpty) }
    }
    var body: some View {
        Screen(title: "녹음 보관함", eyebrow: "로컬 녹음 관리", headerIcon: "square.and.arrow.up", headerAction: { showWorkflow = true }) {
            GlassesRecordingCard()
            NavigationLink("ZIP 내보내기 사본 및 복원 가능한 보관함") { PortableExportCopiesView() }
                .accessibilityIdentifier("export-copies-open")
            HStack(spacing: 0) {
                ForEach(["전체", "텍스트 대기", "메모 있음"], id: \.self) { value in
                    Button { filter = value } label: {
                        Text(value).font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(filter == value ? .white : Palette.ink)
                            .background(filter == value ? Palette.ink : .clear, in: Capsule())
                    }
                }
            }.padding(3).background(Palette.line.opacity(0.35), in: Capsule())
            ArchiveFeedbackView()
            if archive.recordings.isEmpty {
                Card {
                    EmptyState(icon: "waveform.badge.magnifyingglass", title: "녹음이 없습니다", detail: "오디오 파일을 직접 가져올 수 있습니다.\n안경 녹음은 먼저 이 기기에서 수신을 켜세요.")
                        .padding(.top, 25).padding(.bottom, 10)
                    importButton("오디오 파일 가져오기").padding(.horizontal, 20).padding(.bottom, 20)
                }
            } else {
                SectionLabel(title: "검증된 보관함", trailing: "로컬 사본 \(archive.recordings.count)개")
                if visibleRecordings.isEmpty {
                    Card { EmptyState(icon: "line.3.horizontal.decrease.circle", title: "이 분류에 기록이 없습니다", detail: "텍스트는 직접 입력해야 합니다. 이 화면에서는 자동 전사하지 않습니다.") }
                }
                ForEach(visibleRecordings) { recording in
                    NavigationLink { ArchiveDetailView(original: recording) } label: {
                        Card {
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: "waveform").foregroundStyle(Palette.green).frame(width: 38, height: 44).background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(recording.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(2)
                                    Text("\(recording.importedAt.formatted(date: .abbreviated, time: .shortened)) 가져옴 · \(ByteCountFormatter.string(fromByteCount: recording.byteCount, countStyle: .file))")
                                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    Badge(text: archive.verificationIssues[recording.id] != nil ? "검증 오류 · 다시 확인 필요" : (recording.transcripts.isEmpty ? "검증 이력이 있는 사본 · 텍스트 입력 대기" : "Markdown 수정본 \(recording.transcripts.count)개"), active: archive.verificationIssues[recording.id] == nil)
                                    if archive.verificationIssues[recording.id] != nil {
                                        Label("보관 파일 검증 오류 · 상세 보기", systemImage: "exclamationmark.triangle")
                                            .font(.caption2).foregroundStyle(Palette.amber)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                            }.contentShape(Rectangle())
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("archive-row-\(recording.id.uuidString)")
                }
                importButton("계속 가져오기")
            }
            if archive.allowsTestFixture {
                Button { Task { await archive.importTestFixture() } } label: {
                    Label("테스트 샘플 가져오기", systemImage: "testtube.2").font(.footnote)
                }.disabled(archive.isBusy).accessibilityIdentifier("archive-import-fixture")
                Text("개발용 테스트입니다. 실제 오디오가 아니며 누르면 생성합니다.")
                    .font(.caption2).foregroundStyle(Palette.amber)
                #if DEBUG
                Menu {
                    ForEach(ContainerSyntheticFixture.allCases) { fixture in
                        Button(fixture.title) { Task { await archive.importContainerFixture(fixture) } }
                            .accessibilityIdentifier("container-fixture-\(fixture.rawValue)")
                    }
                } label: {
                    Label("테스트 컨테이너 샘플 선택", systemImage: "testtube.2").font(.footnote)
                }.disabled(archive.isBusy).accessibilityIdentifier("container-fixture-menu")
                #endif
            }
            if !store.recordings.isEmpty {
                NavigationLink { LegacyRecordingsView() } label: {
                    Card { FeatureRow(icon: "folder", title: "이전 버전의 가져온 사본", subtitle: "파일 \(store.recordings.count)개를 원래 위치에 유지하며 자동 이전하지 않습니다", status: "보기") }
                }.buttonStyle(.plain).accessibilityIdentifier("legacy-recordings")
            }
            Button { showWorkflow = true } label: {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("내보내기 대상").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Text("NAS / Obsidian").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.ink)
                        Label("Markdown 공유 가능 · 업로드 연동 준비 중", systemImage: "clock").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 5)
                    }
                    Spacer(); Image(systemName: "server.rack").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.green)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain)
            Button("보관함 새로고침 및 복구") { Task { await archive.load() } }.font(.caption).disabled(archive.isBusy)
            Text("직접 가져오기 · 자동 전사 및 업로드 없음").font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
        }
        .task { await archive.load() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, UTType(filenameExtension: "ogg") ?? .audio]) { result in
            switch result {
            case .success(let url): Task { await archive.importFile(url) }
            case .failure(let error): archive.errorMessage = "파일 선택 실패: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showWorkflow) { ArchiveWorkflowView() }
    }
    private func importButton(_ title: String) -> some View {
        PrimaryButton(title: archive.isBusy ? "보관 처리 중…" : title, icon: "square.and.arrow.down", enabled: !archive.isBusy) { showImporter = true }
            .accessibilityIdentifier("archive-import-file")
    }
}

struct ArchiveDetailView: View {
    @EnvironmentObject private var archive: LocalArchiveController
    let original: ArchivedRecording
    @State private var mode = "归档证据"
    @State private var title = ""
    @State private var transcript = ""
    @State private var share: ArchiveShareItem?
    @State private var confirmBundle = false
    @State private var bundleTask: Task<Void,Never>?
    @FocusState private var editing: Bool
    private var recording: ArchivedRecording { archive.recordings.first { $0.id == original.id } ?? original }
    private var integrityIssue: String? { archive.verificationIssues[original.id] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("기기에서 검증된 보관 파일", systemImage: "checkmark.shield").font(.caption).foregroundStyle(Palette.mint)
                    Text(recording.title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text("오디오 디코딩, 음성 인식, 원격 업로드는 실행하지 않았습니다").font(.system(size: 11)).foregroundStyle(Palette.mint.opacity(0.8))
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.ink, in: RoundedRectangle(cornerRadius: 20))
                Picker("보관 파일 상세", selection: $mode) {
                    Text("보관 검증 기록").tag("归档证据"); Text("텍스트 및 수정본").tag("文字与修订")
                }.pickerStyle(.segmented)
                ArchiveFeedbackView()
                if let integrityIssue {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("이 보관 파일에 검증 오류가 있습니다", systemImage: "exclamationmark.triangle").font(.subheadline.weight(.medium))
                        Text(integrityIssue).font(.caption)
                        Text("새로고침하거나 오류를 닫아도 검증 오류는 유지됩니다. 전체 재검증 후 복구하며 이전 검증 이력도 유지합니다.")
                            .font(.caption2)
                    }.foregroundStyle(Palette.amber).padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("archive-persistent-integrity-issue")
                }
                if mode == "归档证据" { evidenceContent } else { transcriptContent }
            }.padding(24)
        }.background(Palette.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle("녹음 상세").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .onAppear { if title.isEmpty { title = recording.title } }
            .sheet(item: $share) { item in ArchiveShareView(item: item) }
            .onDisappear { bundleTask?.cancel() }
            .confirmationDialog("이 녹음과 선택한 수정본만 내보내며 추가 로컬 사본을 생성합니다.",isPresented:$confirmBundle) {
                if let latest = recording.transcripts.last {
                    Button("오디오 + 최신 메모") { exportBundle(.selected([latest.id])) }
                    Button("오디오 + 모든 메모 수정본") { exportBundle(.all) }
                }
                Button("오디오 및 검증 목록만") { exportBundle(.selected([])) }.accessibilityIdentifier("archive-bundle-audio-only")
            }
    }
    private var evidenceContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                evidenceRow("1", title: "원본의 사본을 만들었습니다", detail: "원본은 이동하지 않았습니다. 안경 무선 전송의 완전성을 뜻하지 않습니다", complete: recording.evidence.sourceCopied, id: "evidence-copy")
                Divider().overlay(Palette.line)
                evidenceRow("2", title: integrityIssue == nil ? "보관 파일의 바이트 검증 이력 있음" : "보관 내용 확인 필요", detail: "SHA-256 및 길이 검증 이력이며 오디오 재생 가능 여부와는 별개입니다", complete: recording.evidence.checksumVerified && integrityIssue == nil, id: "evidence-checksum")
                Divider().overlay(Palette.line)
                evidenceRow("3", title: recording.evidence.transcriptProvided ? "사용자 텍스트 보관됨" : "사용자 텍스트 입력 대기", detail: "이 앱은 음성 인식을 실행하지 않았습니다", complete: recording.evidence.transcriptProvided, id: "evidence-transcript")
                Divider().overlay(Palette.line)
                evidenceRow("4", title: recording.evidence.noteExported ? "로컬 Markdown 생성됨" : "Markdown 생성 대기", detail: "NAS 수신이나 Obsidian 인덱싱을 의미하지 않습니다", complete: recording.evidence.noteExported, id: "evidence-note")
            }
            Card {
                Text("검증 기록").font(.headline).foregroundStyle(Palette.ink)
                Text("보관 시 검증: \(recording.checksumVerifiedAt.formatted(date: .abbreviated, time: .standard))")
                if let date = archive.latestVerifications[recording.id] {
                    Text("이번 실행에서 검증: \(date.formatted(date: .abbreviated, time: .standard))")
                } else { Text("목록은 검증 이력입니다. 새로고침해도 모든 오디오를 다시 읽지는 않습니다.") }
                Text("녹음 시간: \(recording.recordedAt?.formatted(date: .abbreviated, time: .shortened) ?? "알 수 없음 · 가져온 시간으로 대체하지 않음")")
                Text("SHA-256\n\(recording.sha256)").font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            }.font(.caption).foregroundStyle(Palette.muted)
            NavigationLink { AudioContainerInspectionView(recordingID: recording.id) } label: {
                Card { FeatureRow(icon: "waveform.path.ecg", title: "오디오 컨테이너 검사", subtitle: "Ogg / Opus 구조 수동 검사 · 디코딩 및 음성 인식 없음", status: "로컬 도구", active: true) }
            }.buttonStyle(.plain).accessibilityIdentifier("archive-open-container-check")
            PrimaryButton(title: "오디오 및 메모 다시 검증", icon: "checkmark.shield", enabled: !archive.isBusy) {
                Task { _ = await archive.verify(recording.id) }
            }.accessibilityIdentifier("archive-verify")
            Button("오디오 사본 검증 후 공유") {
                Task { if let url = await archive.verify(recording.id) { share = ArchiveShareItem(url: url, isMarkdown: false) } }
            }.disabled(archive.isBusy).font(.subheadline).accessibilityIdentifier("archive-share-audio")
            Button("Obsidian / NAS용 ZIP 내보내기") { confirmBundle = true }
                .disabled(archive.isBusy).font(.subheadline).accessibilityIdentifier("archive-export-bundle")
            Text("압축 해제 후 notes/와 audio/의 상대 경로를 유지하세요. API 키나 다른 대화는 포함하지 않습니다. 내보내기는 업로드나 인덱싱 완료가 아닙니다.").font(.caption).foregroundStyle(Palette.muted)
        }
    }
    private func exportBundle(_ selection: SnapshotRevisionSelection) {
        bundleTask = Task {
            if let url = await archive.preparePortableShare(recordingID:recording.id,revisions:selection), !Task.isCancelled {
                share = ArchiveShareItem(url:url,isMarkdown:false,isBundle:true)
            }
        }
    }
    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("텍스트 직접 입력 · ASR 시작 안 함", systemImage: "pencil.line").font(.caption).foregroundStyle(Palette.green)
            Card { ManualRecordingASRView(id: recording.id, title: recording.title) }
            Card {
                Text("메모 제목").font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                TextField("한 줄 제목, 최대 UTF-8 256바이트", text: $title).textInputAutocapitalization(.never)
                    .padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("archive-note-title").focused($editing)
                Text("직접 입력한 텍스트").font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                TextEditor(text: $transcript).frame(minHeight: 170).scrollContentBackground(.hidden)
                    .padding(8).background(Palette.background, in: RoundedRectangle(cornerRadius: 12)).focused($editing).accessibilityIdentifier("archive-transcript")
                Text("현재 \(transcript.utf8.count)바이트 / 1 MiB. 저장하지 않고 나가면 입력한 텍스트가 사라집니다.")
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
            PrimaryButton(title: "로컬 Markdown 수정본으로 저장", icon: "doc.badge.plus", enabled: !archive.isBusy && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                editing = false
                Task { _ = await archive.saveTranscript(recordingID: recording.id, text: transcript, title: title) }
            }.accessibilityIdentifier("archive-save-note")
            Text("텍스트나 제목을 바꾸면 새 수정본을 만듭니다. 같은 입력은 기존 수정본을 사용하며 이전 원고를 덮어쓰지 않습니다.")
                .font(.caption).foregroundStyle(Palette.muted)
            SectionLabel(title: "로컬 수정본", trailing: "수정본 \(recording.transcripts.count)개")
            if recording.transcripts.isEmpty {
                Text("Markdown 수정본이 없습니다").font(.subheadline).foregroundStyle(Palette.muted).accessibilityIdentifier("archive-no-revisions")
            }
            ForEach(recording.transcripts.reversed()) { revision in
                Card {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("수정본 \(revision.number) · \(revision.title)").font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink).accessibilityIdentifier("archive-revision-\(revision.number)")
                            Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button {
                            Task { if let url = await archive.prepareNoteShare(recordingID: recording.id, revisionID: revision.id) { share = ArchiveShareItem(url: url, isMarkdown: true) } }
                        } label: { Image(systemName: "square.and.arrow.up").frame(width: 36, height: 36) }
                            .disabled(archive.isBusy).accessibilityLabel("수정본 \(revision.number) 검증 후 공유").accessibilityIdentifier("archive-share-note-\(revision.number)")
                    }
                }
            }
        }
    }
    private func evidenceRow(_ number: String, title: String, detail: String, complete: Bool, id: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle").foregroundStyle(complete ? Palette.green : Palette.muted)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink).accessibilityIdentifier(id)
                Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ArchiveFeedbackView: View {
    @EnvironmentObject private var archive: LocalArchiveController
    var body: some View {
        if archive.isBusy { ProgressView(archive.activity).font(.caption).frame(maxWidth: .infinity).padding(8) }
        if let error = archive.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label("로컬 작업 미완료", systemImage: "exclamationmark.triangle").font(.subheadline.weight(.medium))
                Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
                Button("오류 설명 접기") { archive.errorMessage = nil }.font(.caption)
            }.foregroundStyle(Palette.amber).padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("archive-error")
        } else if let message = archive.statusMessage {
            Text(message).font(.caption).foregroundStyle(Palette.green).padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("archive-status")
        }
    }
}

struct LegacyRecordingsView: View {
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var archive: LocalArchiveController
    @State private var selected: LocalRecording?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("이전 사본은 원래 폴더에 유지합니다. 자동 이전이나 삭제를 하지 않습니다. 항목을 선택한 경우에만 새 검증 보관함으로 복사합니다.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                ArchiveFeedbackView()
                ForEach(store.recordings) { recording in
                    Card {
                        Text(recording.name).font(.headline).foregroundStyle(Palette.ink)
                        Badge(text: "이전 사본 · 새 보관함 검증 전")
                        if let url = store.recordingURL(recording) {
                            Button("검증 보관함에 복사 (이전 사본 유지)") { selected = recording }.disabled(archive.isBusy)
                            ShareLink(item: url) { Label("이전 오디오 사본 공유", systemImage: "square.and.arrow.up") }.font(.caption)
                        } else { Text("이전 사본을 읽을 수 없습니다. 메타데이터는 유지합니다.").font(.caption).foregroundStyle(Palette.amber) }
                    }
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle("이전 버전의 가져온 사본").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .confirmationDialog("이 항목만 새 검증 보관함으로 복사하며 이전 사본은 유지합니다.", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                Button("이전 사본을 유지하고 복사") {
                    if let recording = selected, let url = store.recordingURL(recording) { Task { await archive.importFile(url, title: recording.name) } }
                    selected = nil
                }
                Button("취소", role: .cancel) { selected = nil }
            }
    }
}

struct ArchiveShareItem: Identifiable {
    let id = UUID()
    let url: URL
    let isMarkdown: Bool
    var isBundle = false
}

struct ArchiveShareView: View {
    @Environment(\.dismiss) private var dismiss
    let item: ArchiveShareItem
    @State private var presentation: ArchiveExportKind?
    @State private var exportError: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Label("로컬 파일만 공유", systemImage: "square.and.arrow.up").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(item.isBundle
                     ? "ZIP의 길이, CRC, SHA-256을 확인했습니다. 선택한 오디오, 메모, 검증 목록이 포함됩니다. 압축 해제 후 notes/와 audio/를 같은 경로에 유지하여 Obsidian에 넣으세요. NAS 업로드나 인덱싱은 하지 않았습니다."
                     : item.isMarkdown
                     ? "공유 전 Markdown 해시를 확인했습니다. 메모만 공유하면 오디오 첨부는 포함되지 않습니다. Obsidian에서는 해당 오디오를 함께 저장하고 notes/와 audio/의 상대 경로를 유지하세요."
                     : "바이트를 재검증한 로컬 사본입니다. 디코딩 가능 여부 확인이나 백그라운드 업로드는 하지 않았습니다.")
                    .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                Text("공유 화면이 열려도 전달 완료는 아닙니다. 대상 앱에서 저장 결과를 확인하세요.")
                    .font(.caption).foregroundStyle(Palette.amber)
                Button { open(.share) } label: {
                    Label("공유 화면 열기", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(17).background(Palette.ink, in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityIdentifier("archive-system-share")
                Button { open(.files) } label: {
                    Label("파일에 저장", systemImage: "folder").frame(maxWidth: .infinity).padding(15)
                }.accessibilityIdentifier("archive-save-files")
                Spacer()
            }.padding(24).background(Palette.background).navigationTitle("로컬 파일 공유").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
        .sheet(item: $presentation) { kind in
            NativeArchiveExportSheet(url: item.url, kind: kind) { error in
                presentation = nil
                if let error { exportError = error }
            }
        }
        .alert("파일 공유를 열 수 없음", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(exportError ?? "") }
    }
    private func open(_ kind: ArchiveExportKind) {
        guard item.url.isFileURL, FileManager.default.isReadableFile(atPath: item.url.path) else {
            exportError = "파일을 읽을 수 없습니다. 녹음 상세에서 다시 검증 후 시도하세요. 원본은 변경되지 않았습니다."; return
        }
        presentation = kind
    }
}

enum ArchiveExportKind: String, Identifiable {
    case share, files
    var id: String { rawValue }
}

/// Present from SwiftUI's actual sheet host, not a guessed root controller.
/// UIKit directly receives the verified local URL; no Transferable metadata hop.
struct NativeArchiveExportSheet: UIViewControllerRepresentable {
    let url: URL
    let kind: ArchiveExportKind
    let completion: (String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIViewController {
        let coordinator = context.coordinator
        if kind == .files {
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            picker.delegate = coordinator
            return picker
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { [weak coordinator] _, _, _, error in
            DispatchQueue.main.async {
                coordinator?.completion(error == nil ? nil : "공유를 완료하지 못했습니다. 다시 시도하거나 파일에 저장하세요. 원본은 유지됩니다.")
            }
        }
        return activity
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (String?) -> Void
        init(completion: @escaping (String?) -> Void) { self.completion = completion }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(nil) // Destination provider owns the copy; never delete source.
        }
    }
}

struct ArchiveWorkflowView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("목소리에서 나만의 지식으로").font(.title2.bold()).foregroundStyle(Palette.ink)
                    Text("원본을 선택하면 기기 전용 폴더에 복사 후 바이트를 검증합니다. 텍스트는 직접 입력하며 수정할 때마다 새 메모를 만들어 이전 원고를 유지합니다.")
                        .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                    Card {
                        FeatureRow(icon: "1.circle", title: "안경에서 휴대폰으로", subtitle: "녹음 동기화, 완전성 및 이어받기는 별도 연동 필요")
                        FeatureRow(icon: "2.circle", title: "기기에서 검증된 보관 파일", subtitle: "파일 직접 선택 · 원본 유지 · SHA-256 중복 제거", status: "로컬 사용 가능", active: true)
                        FeatureRow(icon: "3.circle", title: "직접 입력한 텍스트 및 Markdown", subtitle: "로컬 수정본 및 공유 · 자동 인식 없음", status: "로컬 사용 가능", active: true)
                        FeatureRow(icon: "4.circle", title: "NAS 및 Obsidian", subtitle: "원격 전송, 첨부 경로 및 실제 인덱싱 미검증")
                    }
                    Text("검증은 복사한 바이트에만 적용됩니다. 오디오 디코딩, 무선 수신 완전성, 텍스트 정확도를 보장하지 않습니다. NAS 주소를 미리 설정하거나 공식 앱의 인증 정보를 읽지 않습니다.")
                        .font(.footnote).foregroundStyle(Palette.green)
                }.padding(24)
            }.background(Palette.background).navigationTitle("보관 처리 상태").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }
}
