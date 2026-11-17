import Foundation
import Combine

struct CodexPushEvent: Decodable, Identifiable {
    let id: String
    let taskId: String
    let turnId: String
    let kind: String
    let title: String
    let content: String
    let approvalId: String?
    let createdAt: Double
    let expiresAt: Double
}

/// Automatic delivery while iOS lets the app run. Not an APNs wakeup service.
@MainActor final class CodexPush: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var status = "작업 알림 꺼짐"
    @Published private(set) var pendingCount = 0
    private let codex: CodexCompanion
    private let defaults: UserDefaults
    private let canDeliver: () -> Bool
    private let deliver: (String, String) -> String?
    private let now: () -> Double
    private let prefix = "companion.codex.push.v1."
    private var observedEndpoint: String
    private var since: Double
    private var attempted: [String]
    private var inFlight = false
    private var nextDelivery: Double = 0

    init(codex: CodexCompanion, defaults: UserDefaults, now: @escaping () -> Double = { Date().timeIntervalSince1970 * 1000 },
         canDeliver: @escaping () -> Bool, deliver: @escaping (String, String) -> String?) {
        self.codex = codex; self.defaults = defaults; self.now = now
        self.canDeliver = canDeliver; self.deliver = deliver
        enabled = defaults.bool(forKey: prefix + "enabled")
        since = defaults.double(forKey: prefix + "since")
        observedEndpoint = defaults.string(forKey: prefix + "endpoint") ?? ""
        attempted = Array((defaults.stringArray(forKey: prefix + "attempted") ?? []).suffix(512))
        if enabled { status = "연결 대기 중 · 켠 이후의 새 이벤트만 알림" }
    }
    func setEnabled(_ value: Bool) {
        enabled = value; defaults.set(value, forKey: prefix + "enabled")
        pendingCount = 0
        if value { resetBaseline(); status = "켜짐 · 새 작업 이벤트 대기 중. 안경 전체 알림을 허용하세요" }
        else { status = "작업 알림을 껐습니다. Codex 작업은 계속됩니다" }
    }
    private func resetBaseline() {
        since = now(); observedEndpoint = codex.endpoint; attempted = []; nextDelivery = 0
        defaults.set(since, forKey: prefix + "since")
        defaults.set(observedEndpoint, forKey: prefix + "endpoint")
        defaults.set(attempted, forKey: prefix + "attempted")
    }
    func tick() async {
        guard enabled, codex.configured, !inFlight else { return }
        if observedEndpoint != codex.endpoint { resetBaseline() }
        inFlight = true; defer { inFlight = false }
        let endpoint = codex.endpoint
        await codex.refresh()
        guard enabled, endpoint == codex.endpoint, let state = codex.state, state.online else {
            status = "브리지 오프라인 · 작업 결과를 전송하지 않았습니다"; return
        }
        guard let events = state.events else { status = "브리지가 이벤트 알림을 지원하지 않습니다. PC 브리지를 업데이트하세요"; return }
        let time = now()
        let candidates = events.filter { event in
            guard event.createdAt.isFinite, event.expiresAt.isFinite, event.createdAt >= since,
                  event.createdAt <= time + 30_000, event.expiresAt > time,
                  !attempted.contains(event.id), !event.id.isEmpty, event.id.count <= 128,
                  !event.title.isEmpty, event.title.count <= 80, !event.content.isEmpty, event.content.count <= 500,
                  let task = state.tasks.first(where: { $0.id == event.taskId }) else { return false }
            if ["approval", "question"].contains(event.kind) {
                return task.pending.contains { $0.id == event.approvalId && $0.turnId == event.turnId && $0.expiresAt > time }
            }
            return ["completed", "failed", "interrupted"].contains(event.kind)
        }.sorted { $0.createdAt < $1.createdAt }
        pendingCount = candidates.count
        guard let event = candidates.first else { return }
        guard canDeliver(), time >= nextDelivery else {
            status = "\(pendingCount)개 알림 대기 · 안경 연결, 사용 종료 및 알림 허용 대기 중"; return
        }
        // Persist before transport: never auto-repeat an uncertain hardware send.
        attempted.append(event.id); attempted = Array(attempted.suffix(512))
        defaults.set(attempted, forKey: prefix + "attempted")
        nextDelivery = time + 8000
        let uid = deliver(event.title, event.content)
        pendingCount -= 1
        status = uid.map { "안경 알림 전송됨 UID \($0) · 실제 표시는 알림 상태와 안경에서 확인하세요" }
            ?? "알림 전송 실패 또는 결과 미확인 · 자동 재전송하지 않습니다. 콘솔에서 결과를 확인하세요"
    }
}
