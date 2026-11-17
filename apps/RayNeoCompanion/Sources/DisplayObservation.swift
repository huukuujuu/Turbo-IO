import Foundation
import Combine

/// Opt-in, bounded, memory-only telemetry. No audio, credentials, raw JSON or device IDs.
@MainActor final class DisplayObservation: ObservableObject {
    static let shared = DisplayObservation()
    @Published var enabled = false
    @Published var includesText = false { didSet { if !includesText { question = ""; answer = ""; events.removeAll() } } }
    private(set) var connected = false
    private(set) var phase = "unknown"
    private(set) var page: [String: Any] = [:]
    private(set) var screen: Int64?
    private(set) var question = ""
    private(set) var answer = ""
    private var round: String?
    private(set) var events: [[String: Any]] = []
    private var sequence = 0
    private(set) var session = UUID().uuidString
    private var lastInbound: Double?
    private static func bounded(_ text: String, bytes: Int) -> String {
        // Bound bytes, not grapheme clusters (a single cluster may contain many scalars).
        String(decoding:text.utf8.prefix(bytes),as:UTF8.self)
    }
    func newUtterance() { guard enabled else { return }; question = ""; answer = ""; round = nil }
    private let apps = ["com.rayneo.liteos.recorder":"녹음", "com.rayneo.liteos.aiSubtitle":"자막",
        "com.rayneo.liteos.conversationAssist":"실시간 안내", "com.rayneo.liteos.todo":"할 일",
        "com.rayneo.liteos.prompter":"프롬프터", "com.rayneo.liteos.ai_memory":"일상 기록"]
    func reset() {
        page = [:]; screen = nil; question = ""; answer = ""; round = nil
        events = []; sequence = 0; lastInbound = nil; session = UUID().uuidString
    }
    func connection(_ ready: Bool, phase: String) {
        if connected != ready {
            connected = ready
            if enabled { event("connection", detail: ready ? "안경 한 대 인증 완료" : "안경 연결 불가 · 이전 응답 무효") }
            // A new link must earn a new page observation; never label old data current.
            page = [:]; screen = nil; lastInbound = nil; question = ""; answer = ""; round = nil
        }
        self.phase = String(phase.prefix(60))
    }
    func loss() { guard enabled else { return }; page = [:]; screen = nil; event("loss", detail: "수신 패킷 누락 · 화면 상태 미확인") }
    func voiceMetadata(type: UInt32) {
        guard enabled, connected, ![3,163,164].contains(type) else { return }
        lastInbound = Date().timeIntervalSince1970
        event("received",detail:"도우미 수신 type \(type) · 유형 정보만 관찰",business:13,type:type)
    }
    func packet(_ data: Data, business: UInt8, inbound: Bool) {
        guard enabled, connected, data.count <= 131_100,
              [13,14,15,20,21,22].contains(business), let wire = try? DeviceBusinessWire(data) else { return }
        if business == 13, [3,163,164].contains(wire.type) { return } // Never retain audio.
        if business == 14, !wire.bytes.isEmpty { return }
        let now = Date().timeIntervalSince1970
        if inbound { lastInbound = now }
        var detail = "업무 \(business) / type \(wire.type) · \(data.count) B"
        let j = wire.json
        if inbound, business == 15, wire.type == 24, j["cmd"] as? String == "glass_preview",
           let payload = j["payload"] as? [String: Any], let raw = payload["data"] as? String,
           raw.utf8.count <= 16_384, let bytes = raw.data(using: .utf8),
           let p = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           let scene = DeviceBusinessWire.integer(p,"scence") ?? DeviceBusinessWire.integer(p,"scene") {
            var result: [String:Any] = ["scene":scene,"name":[0:"대시보드",1:"앱 메뉴",2:"앱 화면"][scene] ?? "알 수 없는 화면", "at":now]
            if let index = DeviceBusinessWire.integer(p,"index") { result["index"] = index }
            if let app = p["app"] as? [String:Any] {
                result["app"] = apps[app["name"] as? String ?? ""] ?? "알 수 없는 앱"
                if let action = DeviceBusinessWire.integer(app,"action") { result["action"] = action }
            }
            // Exit is an event, not evidence that the exited app remains on screen.
            if result["action"] as? Int64 == 2 { result["name"] = "앱 종료됨 · 다음 화면 대기 중" }
            page = result; detail = "glass_preview · \(result["name"] ?? "알 수 없음") · \(result["app"] ?? "")"
        }
        if inbound, business == 15, j["cmd"] as? String == "screen_status",
           let payload = j["payload"] as? [String:Any], let value = DeviceBusinessWire.integer(payload,"value") {
            screen = value; detail = "screen_status 원본 값 \(value) (화면 픽셀을 추정하지 않음)"
        }
        var text: String?
        if !inbound, includesText {
            if business == 13, wire.type == 5, let value = j["text"] as? String {
                question = Self.bounded(value,bytes:4096); text = question
            }
            if business == 13, wire.type == 32, let payload = j["answer"] as? [String:Any], let value = payload["text"] as? String {
                let next = j["uuid"] as? String
                if next != round { answer = ""; round = next }
                answer = Self.bounded(answer + value,bytes:16384); text = value
            }
            if business == 21, wire.type == 2 {
                text = ["title","subtitle","content"].compactMap { j[$0] as? String }.joined(separator:"\n")
            }
        }
        event(inbound ? "received" : "submitted", detail: detail, business: business, type: wire.type, text: text)
    }
    private func event(_ kind: String, detail: String, business: UInt8? = nil, type: UInt32? = nil, text: String? = nil) {
        sequence += 1
        var e: [String:Any] = ["id":sequence,"at":Date().timeIntervalSince1970,"kind":kind,"detail":detail]
        if let business { e["business"] = business }; if let type { e["type"] = type }
        if includesText, let text, !text.isEmpty {
            e["text"] = Self.bounded(text,bytes:256)
            e["textTruncated"] = text.utf8.count > 256
        }
        events.append(e); if events.count > 80 { events.removeFirst(events.count - 80) }
    }
    func snapshot() -> [String:Any] {
        var value: [String:Any] = ["version":1,"session":session,"sampledAt":Date().timeIntervalSince1970,
            "connected":connected,"phase":phase,"includesText":includesText,"page":page,
            "question":includesText ? question : "","answer":includesText ? answer : "","events":events,
            "notice":"기기 상태를 재구성한 화면이며 안경 스크린샷은 아닙니다. submitted는 SDK 요청 성공만 의미합니다."]
        if let screen { value["screenRaw"] = screen }; if let lastInbound { value["lastInbound"] = lastInbound }
        return value
    }
}
