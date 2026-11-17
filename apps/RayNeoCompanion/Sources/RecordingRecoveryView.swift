import SwiftUI

struct RecordingRecoveryView: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @State private var selected: String?
    @State private var raw: URL?
    var body: some View {
        List {
            Section("Turbo IO의 로컬 파일만 처리") {
                Text("앱 재시작 후 수신 파일을 찾습니다. 안경 연결, 녹음 시작, 오프라인 재전송 요청이나 원본 삭제는 하지 않습니다. 수신 완료 기록과 데이터 범위가 확인된 항목만 복구를 시도합니다.")
                    .font(.caption)
                Button("기기의 수신 폴더 검색") { Task { await features.loadRecoveryEntries() } }
                    .disabled(features.recoveryBusy || features.recordingID != nil).accessibilityIdentifier("recovery-scan")
                Text(features.recoveryStatus).font(.caption).accessibilityIdentifier("recovery-status")
                if features.recoveryBusy { ProgressView() }
            }
            if features.recoveryEntries.isEmpty {
                Text("기기에 수신 기록이 없습니다").foregroundStyle(.secondary).accessibilityIdentifier("recovery-empty")
            }
            ForEach(features.recoveryEntries) { entry in
                Section("로컬 수신: " + entry.createdAt.formatted(date:.abbreviated,time:.shortened)) {
                    Text(entry.status).font(.subheadline)
                    Text("기록됨: \(ByteCountFormatter.string(fromByteCount:Int64(entry.receivedBytes),countStyle:.file)) · 로컬 ID \(entry.id.prefix(8))").font(.caption)
                    Button("다시 검증, 디코딩 및 보관") { selected = entry.id }
                        .disabled(!entry.mayRecover || features.recoveryBusy || features.recordingID != nil)
                    Button("원본 rawopus 공유 준비 (완전성 미확인)") {
                        Task { raw = await features.recoveryRawFile(entry.id) }
                    }.disabled(features.recoveryBusy || features.recordingID != nil)
                }
            }
            if let raw {
                Section("원시 데이터 · 재생 가능 여부 미확인") {
                    Text("이 rawopus는 불완전할 수 있으며 백업·연구용입니다. 오디오 복구나 음성 인식은 하지 않습니다. 공유 화면이 열려도 전달 완료를 의미하지 않습니다.").font(.caption)
                    ShareLink(item:raw) { Label("선택한 원본 파일 공유",systemImage:"square.and.arrow.up") }
                }
            }
        }.navigationTitle("수신 파일 복구")
        .task { await features.loadRecoveryEntries() }
        .onDisappear { raw = nil }
        .confirmationDialog("선택한 파일만 다시 검증, 디코딩 및 보관합니다. 업로드하거나 삭제하지 않습니다.",isPresented:Binding(get:{ selected != nil },set:{ if !$0 { selected = nil } })) {
            Button("로컬 복구 시도") {
                if let id = selected { Task { await features.recoverRecording(id) } }
                selected = nil
            }
        }
    }
}
