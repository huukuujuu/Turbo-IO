import SwiftUI

struct ReminderImportView: View {
    @EnvironmentObject private var store: CompanionStore
    @StateObject private var reader = ReminderImportController.forCurrentLaunch()
    @State private var selectedList = ""
    @State private var confirmImport = false
    @State private var showCompleted = false
    var body: some View {
        List {
            Section {
                Text("iPhone 미리 알림에서 선택 항목 가져오기").font(.headline)
                Text("권한 허용 후 목록을 선택하세요. 선택한 항목의 제목, 완료 상태, 예정 시간만 복사하며 메모, 첨부, 위치, 연락처는 가져오지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("iOS 17 이상에서는 권한 이름이 전체 접근이지만 Turbo IO는 읽기만 합니다. 시스템 항목을 수정하거나 자동으로 안경에 보내거나 알림을 생성하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if reader.isFixture {
                    Text("테스트 모드 · 시스템 데이터 읽기 없음").foregroundStyle(Palette.amber).accessibilityIdentifier("reminders-fixture-banner")
                }
                Button("권한 허용 및 목록 읽기") { Task { selectedList = ""; await reader.loadLists() } }
                    .disabled(reader.busy).accessibilityIdentifier("reminders-authorize")
                Text(reader.status).font(.caption).accessibilityIdentifier("reminders-status")
                if let error = reader.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
                if reader.busy { ProgressView("읽는 중…") }
            }
            if !reader.lists.isEmpty {
                Section("목록 선택") {
                    Picker("시스템 목록", selection: Binding(get: { selectedList }, set: { selectedList = $0; reader.cancel() })) {
                        Text("선택하세요").tag("")
                        ForEach(reader.lists) { list in Text(list.title).tag(list.id) }
                    }.disabled(reader.busy).accessibilityIdentifier("reminders-list-picker")
                    Button("선택한 목록 읽기") { Task { await reader.loadReminders(listID: selectedList) } }
                        .disabled(selectedList.isEmpty || reader.busy).accessibilityIdentifier("reminders-read-list")
                    Text("선택한 목록만 읽습니다. 스마트 목록 규칙은 포함하지 않습니다. 최대 500개를 지원하며 한도를 초과하면 일부만 전체 목록인 것처럼 표시하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !reader.rows.isEmpty {
                Section("가져올 항목 선택") {
                    Toggle("완료한 항목 표시", isOn: $showCompleted)
                    Text("\(reader.selected.count)개 선택됨 (최대 100개). 완료한 항목을 숨기면 잘못 가져오지 않도록 선택을 해제합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(reader.rows.filter { showCompleted || !$0.completed }) { row in
                        Button { reader.toggle(row.id) } label: {
                            HStack(alignment: .top) {
                                Image(systemName: reader.selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(row.title).foregroundStyle(Palette.ink)
                                    Text(row.completed ? "시스템에서 완료됨" : "시스템에서 미완료").font(.caption).foregroundStyle(.secondary)
                                    if let day = SystemReminderSnapshot.dateOnlyLabel(row.dueComponents) { Text(day).font(.caption) }
                                    else if let due = row.dueAt { Text(due.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
                                }
                            }
                        }.accessibilityIdentifier("reminders-row-\(row.id)")
                    }
                    Button("Turbo IO로 가져오기 (\(reader.selected.count)개)") { confirmImport = true }
                        .disabled(reader.selected.isEmpty || reader.busy).accessibilityIdentifier("reminders-import")
                    Text("한 번 복사하며 지속 동기화하지 않습니다. 제목은 최대 300자입니다. 반복 규칙, 하위 작업, 메모, 시스템 알림은 복사하지 않으며 원본은 유지합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("읽기 미리보기 지우기") { reader.discardPreview(); selectedList = "" }
                    .accessibilityIdentifier("reminders-clear")
                Text("같은 출처 ID의 항목은 보관된 항목을 포함하여 건너뜁니다. 편집을 덮어쓰거나 자동 복원하지 않습니다. 시스템에서 ID를 다시 만들면 새 항목으로 인식할 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("시스템 미리 알림").navigationBarTitleDisplayMode(.inline)
            .onChange(of: showCompleted) { _ in reader.clearSelection() }
            .onDisappear { reader.discardPreview() }
            .confirmationDialog("선택한 항목을 Turbo IO로 복사할까요? 시스템 미리 알림을 수정하거나 바로 안경에 보내지 않습니다.", isPresented: $confirmImport) {
                Button("Turbo IO로 가져오기 확인") { reader.importSelected(into: store) }
            }
    }
}
