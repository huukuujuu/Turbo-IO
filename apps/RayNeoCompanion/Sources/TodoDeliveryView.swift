import SwiftUI

struct TodoDeliveryView: View {
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var confirmRetry = false
    private var rows: [LocalTodo] { store.todos.filter { $0.archivedAt == nil } }
    var body: some View {
        List {
            Section {
                Text("편집 내용은 다음 전송까지 보관됩니다. 다시 연결해도 일괄 재전송하지 않습니다. 새 항목의 첫 전송은 할 일 화면에서 확인해야 합니다.")
                Text("전송됨은 안경의 항목별 수신 확인이 아닙니다. 완료 상태 응답만으로 제목 버전 전달을 확인할 수 없으며 예정 시간은 전송하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("연결된 항목의 변경 전송 재시도") { confirmRetry = true }
                    .disabled(!voice.ready || !rows.contains { $0.wireID != nil && $0.delivery?.pending == true })
                    .accessibilityIdentifier("todo-retry-pending")
                Text(features.todoStatus).font(.caption)
                if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
            }
            Section("이 기기의 전송 기록") {
                if rows.isEmpty { Text("할 일 전송 기록이 없습니다").accessibilityIdentifier("todo-delivery-empty") }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.title).font(.headline)
                        Text(row.deliveryDescription).font(.caption)
                        if let date = row.delivery?.submittedAt {
                            Text("최근 전송: " + date.formatted(date: .abbreviated, time: .standard)).font(.caption2)
                        }
                        if let observed = row.delivery?.conflict {
                            Text("휴대폰: \(row.completed ? "완료됨" : "미완료") · 안경 응답: \(observed.completed ? "완료됨" : "미완료")")
                                .font(.caption)
                            Text("중요 표시: 휴대폰 \((row.important ?? false) ? "예" : "아니요") · 안경 \(observed.important.map { $0 ? "예" : "아니요" } ?? "제공 안 됨")")
                                .font(.caption)
                            Text("기기의 제목과 예정 시간은 유지합니다. 아래 선택은 충돌만 해결하며 바로 전송하지 않습니다.")
                                .font(.caption2).foregroundStyle(.secondary)
                            Button("휴대폰 상태 유지 후 전송 대기에 추가") { store.resolveTodoConflict(row.id, useGlassesStatus: false) }
                                .buttonStyle(.borderless)
                            Button("안경 상태 적용 · 휴대폰 제목 유지") { store.resolveTodoConflict(row.id, useGlassesStatus: true) }
                                .buttonStyle(.borderless)
                        }
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle("전송 대기 및 충돌").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("현재 안경과 연결된 변경 사항을 다시 전송할까요? 휴대폰에만 있는 새 항목은 전송하지 않습니다.", isPresented: $confirmRetry) {
                Button("전송 재시도") { features.syncTodos(pendingOnly: true) }
            }
    }
}
