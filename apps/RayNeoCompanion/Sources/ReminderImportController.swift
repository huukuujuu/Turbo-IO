import Foundation
import Combine

@MainActor final class ReminderImportController: ObservableObject {
    @Published private(set) var lists: [SystemReminderList] = []
    @Published private(set) var rows: [SystemReminderSnapshot] = []
    @Published private(set) var busy = false
    @Published private(set) var activeList: String?
    @Published private(set) var status = "시스템 미리 알림 읽기 전"
    @Published private(set) var error: String?
    @Published private(set) var selected: Set<String> = []
    let isFixture: Bool
    private let reader: SystemReminderReading
    private var generation = UUID()

    init(reader: SystemReminderReading, isFixture: Bool = false) { self.reader = reader; self.isFixture = isFixture }
    static func forCurrentLaunch() -> ReminderImportController {
        #if DEBUG && !COMPANION_DEVICE
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-reminders-fixture"), let index = args.firstIndex(of: "--ui-test-scope"),
           args.indices.contains(index + 1), UUID(uuidString: args[index + 1]) != nil {
            return ReminderImportController(reader: FixtureReminderReader(), isFixture: true)
        }
        #endif
        return ReminderImportController(reader: EventKitReminderReader())
    }
    private func begin() -> UUID {
        cancel(); generation = UUID(); busy = true; error = nil
        return generation
    }
    func loadLists() async {
        let token = begin(); lists = []; activeList = nil
        status = "권한 및 목록 이름 읽기 대기 중…"
        defer { if generation == token { busy = false } }
        do {
            try await reader.requestAccess()
            guard generation == token, !Task.isCancelled else { return }
            lists = try reader.lists()
            status = lists.isEmpty ? "읽을 수 있는 시스템 목록이 없습니다" : "목록을 선택한 뒤 항목을 읽으세요"
        } catch { if generation == token { fail(error) } }
    }
    func loadReminders(listID: String) async {
        let token = begin(); activeList = listID
        status = "선택한 목록 읽는 중…"
        defer { if generation == token { busy = false } }
        do {
            guard lists.contains(where: { $0.id == listID }) else { throw SystemReminderError.unavailable }
            guard reader.canRead else { throw SystemReminderError.denied }
            let result = try await reader.reminders(in: listID)
            guard generation == token, !Task.isCancelled else { return }
            guard reader.canRead else { throw SystemReminderError.denied }
            guard result.count <= 500 else { throw SystemReminderError.limit }
            guard Set(result.map(\.id)).count == result.count else { throw SystemReminderError.selection }
            rows = result.sorted { lhs, rhs in
                if lhs.completed != rhs.completed { return !lhs.completed }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            status = "읽음 \(rows.count)개 항목 · 선택 후 가져오며 지속 동기화하지 않습니다"
        } catch { if generation == token { fail(error) } }
    }
    func toggle(_ id: String) {
        guard !busy, rows.contains(where: { $0.id == id }) else { return }
        if selected.contains(id) { selected.remove(id) }
        else if selected.count < 100 { selected.insert(id) }
        else { error = SystemReminderError.limit.localizedDescription }
    }
    func clearSelection() { selected = [] }
    func importSelected(into store: CompanionStore) {
        guard !busy else { return }
        do {
            guard reader.canRead else { throw SystemReminderError.denied }
            let report = try store.importSystemReminders(rows, selectedIDs: selected)
            selected = []; error = nil
            status = "가져옴 \(report.imported)개 · 이미 가져온 항목 제외 \(report.skipped)개 · Turbo IO에만 저장"
        } catch { fail(error) }
    }
    func cancel() {
        generation = UUID(); reader.cancel(); busy = false
        rows = []; selected = []
    }
    func discardPreview() {
        cancel(); lists = []; activeList = nil; error = nil
        status = "미리보기를 지웠습니다. 이미 가져온 할 일은 유지됩니다"
    }
    private func fail(_ failure: Error) {
        rows = []; selected = []
        if case SystemReminderError.denied = failure { lists = []; activeList = nil }
        error = (failure as? SystemReminderError)?.localizedDescription ?? SystemReminderError.failed.localizedDescription
        status = "시스템 미리 알림을 가져오거나 수정하지 않았습니다"
    }
}

#if DEBUG && !COMPANION_DEVICE
@MainActor private final class FixtureReminderReader: SystemReminderReading {
    var canRead = true
    func requestAccess() async throws {}
    func lists() throws -> [SystemReminderList] { [SystemReminderList(id: "synthetic-list", title: "테스트 목록 · 시스템 데이터 읽기 없음")] }
    func reminders(in listID: String) async throws -> [SystemReminderSnapshot] {
        [SystemReminderSnapshot(id: "synthetic-reminder", title: "시스템 할 일 가져오기 테스트", completed: false,
            dueComponents: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 9, day: 9))]
    }
    func cancel() {}
}
#endif
