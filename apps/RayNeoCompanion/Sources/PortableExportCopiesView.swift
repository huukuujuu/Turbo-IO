import SwiftUI

struct PortableExportCopiesView: View {
    @EnvironmentObject private var archive: LocalArchiveController
    @State private var selected: PortableExportCopy?
    var body: some View {
        List {
            Section {
                Text("ZIP 내보내기 중 생성한 사본 폴더만 관리합니다. 원본 녹음, 수신 캐시, 텍스트 수정본은 건드리지 않습니다.")
                Text("보관함으로 이동한 사본은 복원할 수 있습니다. 내보내기 개수 제한은 줄지만 디스크 공간은 그대로 사용합니다. 각각 최대 20개이며 자동·영구 삭제하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("폴더 검색은 내용 검증이 아닙니다. 다시 공유하려면 녹음 상세에서 새 검증 패키지를 만드세요.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("사본 목록 새로고침") { Task { await archive.loadExportCopies() } }.disabled(archive.isBusy)
                if archive.exportCopies.unrecognized > 0 {
                    Text("\(archive.exportCopies.unrecognized)개의 알 수 없거나 오류가 있는 폴더는 이동하지 않고 그대로 둡니다.")
                        .foregroundStyle(Palette.amber)
                }
                if let error = archive.errorMessage { Text(error).foregroundStyle(Palette.amber) }
                if let status = archive.statusMessage { Text(status).font(.caption) }
            }
            ForEach([false, true], id: \.self) { trash in
                Section(trash ? "복원 가능한 임시 보관함" : "내보내기 사본") {
                    let rows = archive.exportCopies.copies.filter { $0.inTrash == trash }
                    if rows.isEmpty { Text(trash ? "임시 보관함이 비어 있습니다" : "내보내기 사본이 없습니다") }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("내보내기 " + row.id.uuidString.prefix(8)).font(.headline)
                            Text(row.modifiedAt.formatted(date: .abbreviated, time: .shortened) + " · " + ByteCountFormatter.string(fromByteCount: row.bytes, countStyle: .file)).font(.caption)
                            Button(trash ? "이 사본 복원" : "임시 보관함으로 이동") { selected = row }
                                .disabled(archive.isBusy).buttonStyle(.borderless)
                                .accessibilityIdentifier("export-copy-move-\(row.id.uuidString)")
                        }
                    }
                }
            }
        }.navigationTitle("ZIP 내보내기 사본").navigationBarTitleDisplayMode(.inline)
            .task { await archive.loadExportCopies() }
            .confirmationDialog(selected.map { "\($0.inTrash ? "복원" : "임시 보관")내보내기 사본 \($0.id.uuidString.prefix(8))? 파생 사본만 이동하며 원본은 유지합니다." } ?? "작업 확인",
                isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                if let row = selected {
                    Button(row.inTrash ? "사본 복원 확인" : "임시 보관함으로 이동 확인") {
                        selected = nil
                        Task { await archive.moveExportCopy(row.id, toTrash: !row.inTrash) }
                    }
                }
            }
    }
}
