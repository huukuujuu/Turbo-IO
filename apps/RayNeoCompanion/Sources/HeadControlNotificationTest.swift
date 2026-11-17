import Foundation
import SwiftUI
import RayNeoDisplay

/// A deliberately isolated, on-device test for the observed suggestion-card
/// lifecycle. It does not call a network service, execute a tool, or turn a
/// head gesture into an approval outside this test page.
@MainActor
final class HeadControlNotificationTest: ObservableObject {
    @Published private(set) var status = "테스트 카드 전송 전"
    @Published private(set) var lastDecision: String?
    @Published private(set) var error: String?
    @Published private(set) var pendingID: String?
    @Published private(set) var expiresAt: Date?

    private let device: () -> String?
    private let available: () -> Bool
    private let transport: (UInt8, Data) throws -> Void
    private let now: () -> Date
    private let timeout: TimeInterval
    private let scheduleTimers: Bool
    private var pendingDevice: String?
    private var expiryTask: Task<Void, Never>?
    private let cardCodec = SuggestionCardJSONCodec()
    private let operationCodec = SuggestionJSONCodec()

    init(device: @escaping () -> String?, available: @escaping () -> Bool,
         transport: @escaping (UInt8, Data) throws -> Void,
         now: @escaping () -> Date = Date.init, timeout: TimeInterval = 30,
         scheduleTimers: Bool = true) {
        self.device = device
        self.available = available
        self.transport = transport
        self.now = now
        self.timeout = timeout
        self.scheduleTimers = scheduleTimers
    }

    deinit { expiryTask?.cancel() }

    var canSend: Bool { pendingID == nil && device() != nil && available() }
    var hasPendingCard: Bool { pendingID != nil }

    func send(title: String, source: String, content: String) {
        guard canSend, let connectedDevice = device() else {
            error = "연결된 안경 한 대가 사용 중이 아니어야 합니다. 테스트 카드를 보내지 않았습니다."
            return
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanSource.isEmpty, !cleanContent.isEmpty else {
            error = "제목, 출처, 내용을 모두 입력하세요."
            return
        }

        let id = UUID().uuidString.lowercased()
        do {
            try sendMessage(cardCodec.encodeAppRequest(.add(
                suggestUID: id, suggestType: .todo,
                title: cleanTitle, source: cleanSource, content: cleanContent,
                timeRange: nil)))
            pendingID = id
            pendingDevice = connectedDevice
            expiresAt = now().addingTimeInterval(timeout)
            lastDecision = nil
            error = nil
            status = "테스트 카드 전송됨 · 끄덕임 또는 고개 젓기 대기 중"
            scheduleExpiry(for: id)
        } catch {
            self.error = "테스트 카드 전송 실패: \(error.localizedDescription)"
        }
    }

    /// Explicitly removes only the card created by this page. No acknowledgement
    /// or external action is emitted for a locally cancelled test.
    func cancel() {
        guard let id = pendingID else { return }
        do {
            try sendMessage(cardCodec.encodeAppRequest(.delete(suggestUID: id, suggestType: .todo)))
            clearPending(status: "테스트 카드 제거 요청됨", decision: nil)
        } catch {
            self.error = "테스트 카드 제거 실패: \(error.localizedDescription)"
        }
    }

    func connectionChanged() {
        guard pendingID != nil else { return }
        clearPending(status: "연결 변경 · 이 테스트 카드 대기를 중지했습니다", decision: nil)
    }

    func receive(device incomingDevice: String, wire: DeviceBusinessWire) {
        guard wire.type == 34, let id = pendingID, incomingDevice == pendingDevice else { return }
        do {
            let payload = try JSONSerialization.data(withJSONObject: wire.json, options: [.sortedKeys])
            guard case let .operation(operation) = try operationCodec.decodeGlassesOperation(type: 34, payload: payload),
                  operation.suggestUID == id, operation.suggestType == SuggestionCardCategory.todo.rawValue else { return }
            switch operation.command {
            case .accept: complete(id: id, decision: "끄덕여 확인한 결과 수신됨 (테스트 응답만)")
            case .reject: complete(id: id, decision: "고개를 저어 취소한 결과 수신됨 (테스트 응답만)")
            case .unknown: return
            }
        } catch {
            self.error = "일치하지 않는 머리 동작 응답을 무시했습니다."
        }
    }

    private func complete(id: String, decision: String) {
        // Consume locally before outbound cleanup so duplicate BLE delivery can
        // never turn into a second decision or second acknowledgement.
        clearPending(status: decision, decision: decision)
        do {
            try sendMessage(cardCodec.encodeAppRequest(.delete(suggestUID: id, suggestType: .todo)))
            try sendMessage(operationCodec.encodeAppAcknowledgement(
                suggestUID: id, suggestType: SuggestionCardCategory.todo.rawValue, code: .success))
            error = nil
        } catch {
            self.error = "머리 동작 결과를 기록했지만 정리/확인 응답 전송 실패: \(error.localizedDescription)"
        }
    }

    private func scheduleExpiry(for id: String) {
        expiryTask?.cancel()
        guard scheduleTimers else { return }
        let nanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
        expiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return }
            guard !Task.isCancelled else { return }
            self?.expire(id: id)
        }
    }

    private func expire(id: String) {
        guard pendingID == id else { return }
        do { try sendMessage(cardCodec.encodeAppRequest(.delete(suggestUID: id, suggestType: .todo))) }
        catch let caught { self.error = "테스트 시간 초과 · 제거 요청 전송 실패: \(caught.localizedDescription)" }
        clearPending(status: "테스트 시간 초과 · 아무 작업도 실행하지 않습니다", decision: nil)
    }

    private func clearPending(status: String, decision: String?) {
        expiryTask?.cancel(); expiryTask = nil
        pendingID = nil; pendingDevice = nil; expiresAt = nil
        self.status = status
        if let decision { lastDecision = decision }
    }

    private func sendMessage(_ message: DisplayJSONMessage) throws {
        guard let json = try JSONSerialization.jsonObject(with: message.payload) as? [String: Any] else {
            throw DeviceFeatureError.invalidPacket
        }
        try transport(21, DeviceBusinessWire.encode(type: UInt32(message.type), json: json))
    }
}

struct HeadControlNotificationTestView: View {
    @EnvironmentObject private var test: HeadControlNotificationTest
    @State private var title = "머리 동작 테스트"
    @State private var source = "Turbo IO"
    @State private var content = "끄덕여 확인하고 고개를 저어 취소하세요."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    Label("로컬 머리 동작 테스트", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                    Text("할 일 제안 카드 한 장만 보냅니다. 끄덕임과 고개 젓기 결과는 이 화면에만 표시하며 네트워크, Core 또는 자동화를 실행하지 않습니다.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    TextField("제목", text: $title).textInputAutocapitalization(.never)
                    TextField("출처", text: $source).textInputAutocapitalization(.never)
                    TextField("내용", text: $content, axis: .vertical).lineLimit(2...4)
                    Button("30초 머리 동작 테스트 카드 전송") { test.send(title: title, source: source, content: content) }
                        .disabled(!test.canSend).accessibilityIdentifier("head-control-test-send")
                    if test.hasPendingCard {
                        Button("테스트 카드 즉시 제거", role: .destructive) { test.cancel() }
                            .accessibilityIdentifier("head-control-test-cancel")
                    }
                }
                Card {
                    Text(test.status).font(.subheadline).accessibilityIdentifier("head-control-test-status")
                    if let decision = test.lastDecision { Text(decision).font(.caption).foregroundStyle(Palette.green) }
                    if let error = test.error { Text(error).font(.caption).foregroundStyle(.red) }
                    Text("프로토콜: business 21, type 33 전송, 일치하는 type 34 응답 후 삭제 및 type 35 확인 전송. 검증되지 않은 응답은 무시합니다.")
                        .font(.caption2).foregroundStyle(Palette.muted)
                }
            }.padding(22)
        }
        .background(Palette.background)
        .navigationTitle("머리 동작 알림 테스트")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}
