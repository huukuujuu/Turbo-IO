import Foundation
import Combine
import Security

enum CodexBridgeError: LocalizedError {
    case configuration, missingKey, offline, invalidResponse, rejected(String), unknownDelivery
    var errorDescription: String? {
        switch self {
        case .configuration: return "계정이나 쿼리 매개변수가 없는 HTTPS 브리지 주소를 입력하세요. HTTP 루프백은 시뮬레이터에서만 허용합니다."
        case .missingKey: return "이 브리지 주소의 전용 액세스 토큰을 먼저 저장하세요."
        case .offline: return "브리지에 연결되지 않았습니다. PC 서비스와 네트워크를 확인하세요."
        case .invalidResponse: return "브리지 응답이 유효하지 않거나 버전이 맞지 않습니다."
        case .rejected(let code): return "브리지가 요청을 거부했습니다 (\(code)). 자동 재시도하지 않습니다."
        case .unknownDelivery: return "이전 요청 결과를 확인할 수 없습니다. 이전 요청 확인을 누르고 중복 작업은 만들지 마세요."
        }
    }
}

enum CodexEndpoint {
    static func normalize(_ text: String, allowLoopback: Bool = false) throws -> String {
        guard var c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.url != nil, c.path.isEmpty || c.path == "/",
              c.scheme == "https" || (allowLoopback && c.scheme == "http" && ["127.0.0.1", "localhost", "[::1]", "::1"].contains(host)) else { throw CodexBridgeError.configuration }
        c.path = ""; c.host = host.lowercased()
        return c.string!
    }
    static var simulatorLoopback: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

enum CodexTokenVault {
    static func get(_ endpoint: String) -> String? {
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "io.turboio.codex", kSecAttrAccount as String: endpoint, kSecReturnData as String: true]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String, endpoint: String) throws {
        guard token.range(of: "^[A-Za-z0-9_-]{32,256}$", options: .regularExpression) != nil else { throw CodexBridgeError.missingKey }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "io.turboio.codex", kSecAttrAccount as String: endpoint]
        let attrs: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let rc = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if rc == errSecItemNotFound {
            guard SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw CodexBridgeError.missingKey }
        } else if rc != errSecSuccess { throw CodexBridgeError.missingKey }
    }
}

struct CodexQuestion: Decodable, Identifiable { let id: String; let question: String; let options: [String] }
struct CodexApproval: Decodable, Identifiable {
    let id: String; let taskId: String; let turnId: String; let kind: String; let summary: String
    let questions: [CodexQuestion]; let expiresAt: Double
}
struct CodexTaskState: Decodable, Identifiable {
    let id: String; let threadId: String; let turnId: String?; let status: String; let answer: String; let pending: [CodexApproval]
}
struct CodexBridgeState: Decodable {
    let protocolVersion: Int; let online: Bool; let workspace: String; let readOnly: Bool; let tasks: [CodexTaskState]
    let events: [CodexPushEvent]?
}
private final class CodexNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum CodexHTTP {
    static func call(endpoint: String, token: String, path: String, body: Data?) async throws -> Data {
        let allowed = ["/v1/state", "/v1/message", "/v1/stop", "/v1/decision"]
        guard allowed.contains(path), token.range(of: "^[A-Za-z0-9_-]{32,256}$", options: .regularExpression) != nil else { throw CodexBridgeError.configuration }
        let base = try CodexEndpoint.normalize(endpoint, allowLoopback: CodexEndpoint.simulatorLoopback)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 35; config.timeoutIntervalForResource = 40
        config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: CodexNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw CodexBridgeError.invalidResponse }
        var data = Data()
        for try await byte in bytes { try Task.checkCancellation(); data.append(byte); guard data.count <= 2_097_152 else { throw CodexBridgeError.invalidResponse } }
        guard http.statusCode == 200 else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let raw = object?["error"] as? String ?? "http_\(http.statusCode)"
            let safe = raw.range(of: "^[a-z0-9_]{1,80}$", options: .regularExpression) != nil ? raw : "request_failed"
            throw CodexBridgeError.rejected(safe)
        }
        return data
    }
}

/// One catalogue supplies both the model request and the read-only tools UI.
struct CodexToolDescriptor: Identifiable {
    let id: String
    let title: String
    let description: String
    let example: String
    let requiresText: Bool
    var definition: [String: Any] {
        ["type": "function", "function": ["name": id, "description": description,
            "parameters": ["type": "object", "properties": requiresText ? ["text": ["type": "string", "description": "사용자가 Codex에 요청한 전체 내용. 권한을 임의로 추가하지 않음"]] : [:],
                "required": requiresText ? ["text"] : [], "additionalProperties": false]]]
    }
    var schemaJSON: String {
        guard let data = try? JSONSerialization.data(withJSONObject: definition, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "도구 정의를 표시할 수 없음" }
        return text
    }
    static let all: [Self] = [
        .init(id: "codex_message", title: "작업 시작 / 계속", description: "사용자가 Codex 작업 시작이나 계속을 명확히 요청한 경우에만 호출합니다. 선택한 작업에 보내며 선택하지 않았을 때만 새로 만듭니다. 일반 대화나 권한 승인에는 사용하지 않습니다.", example: "Codex로 이 프로젝트의 폴더 구조를 확인해 줘", requiresText: true),
        .init(id: "codex_status", title: "진행 상황 및 결과 조회", description: "사용자가 현재 Codex 작업의 진행 상황이나 결과를 물을 때 호출합니다.", example: "Codex 작업 끝났어? 결과가 뭐야?", requiresText: false),
        .init(id: "codex_stop", title: "현재 작업 중지", description: "사용자가 현재 Codex 작업 중지를 명확히 요청했을 때만 호출합니다. 응답 읽기를 멈추는 것과 Codex 작업 중지는 다릅니다.", example: "현재 Codex 작업을 중지해 줘", requiresText: false)
    ]
}

/// Tool calls cannot approve: approvals only enter through the explicit native UI.
@MainActor final class CodexCompanion: ObservableObject {
    @Published private(set) var endpoint: String
    @Published private(set) var voiceToolsEnabled: Bool
    @Published private(set) var state: CodexBridgeState?
    @Published private(set) var status = "PC 브리지 연결 전"
    @Published private(set) var busy = false
    @Published private(set) var selectedTaskID: String?
    @Published private(set) var hasUnknownDelivery = false
    @Published private(set) var lastDeliveryError: String?
    private let defaults: UserDefaults
    private let key: (String) -> String?
    private let send: (String, String, String, Data?) async throws -> Data
    private var refreshing = false
    private var generation = UUID()
    private let prefix = "companion.codex.v1."
    var selected: CodexTaskState? { state?.tasks.first { $0.id == selectedTaskID } }
    var configured: Bool { !endpoint.isEmpty && key(endpoint) != nil }
    init(defaults: UserDefaults = .standard, key: @escaping (String) -> String? = CodexTokenVault.get,
         send: @escaping (String, String, String, Data?) async throws -> Data = CodexHTTP.call) {
        self.defaults = defaults; self.key = key; self.send = send
        endpoint = defaults.string(forKey: "companion.codex.v1.endpoint") ?? ""
        voiceToolsEnabled = defaults.bool(forKey: "companion.codex.v1.voiceTools")
        selectedTaskID = defaults.string(forKey: "companion.codex.v1.selected")
        hasUnknownDelivery = defaults.data(forKey: "companion.codex.v1.pending") != nil
        lastDeliveryError = defaults.string(forKey: "companion.codex.v1.deliveryError")
    }
    func save(endpoint input: String, token: String, voiceTools: Bool) throws {
        guard !busy, !hasUnknownDelivery else { throw CodexBridgeError.unknownDelivery }
        let normalized = try CodexEndpoint.normalize(input, allowLoopback: CodexEndpoint.simulatorLoopback)
        if !token.isEmpty { try CodexTokenVault.save(token, endpoint: normalized) }
        guard key(normalized) != nil else { throw CodexBridgeError.missingKey }
        if normalized != endpoint { selectedTaskID = nil; defaults.removeObject(forKey: prefix + "selected") }
        generation = UUID(); state = nil; endpoint = normalized; voiceToolsEnabled = voiceTools
        defaults.set(endpoint, forKey: prefix + "endpoint"); defaults.set(voiceTools, forKey: prefix + "voiceTools")
        status = "설정 저장됨 · 서비스 연결 전. 음성 도구 \(voiceTools ? "허용됨" : "꺼짐")"
    }
    func select(_ id: String?) {
        guard !busy, !hasUnknownDelivery, id == nil || state?.tasks.contains(where: { $0.id == id }) == true else { return }
        selectedTaskID = id; defaults.set(id, forKey: prefix + "selected")
    }
    func refresh() async {
        guard !refreshing, configured else { return }; refreshing = true; defer { refreshing = false }
        let current = generation, base = endpoint
        do {
            let data = try await send(base, key(base)!, "/v1/state", nil)
            let value = try JSONDecoder().decode(CodexBridgeState.self, from: data)
            guard current == generation else { return }
            guard value.protocolVersion == 1, value.tasks.count <= 16, (value.events?.count ?? 0) <= 128 else { throw CodexBridgeError.invalidResponse }
            state = value; status = value.online ? "PC 브리지 온라인 · \(value.readOnly ? "읽기 전용 테스트" : "작업 공간 쓰기 가능 · 승인 요청마다 확인 필요")" : "Codex 프로세스 오프라인"
        } catch {
            guard current == generation else { return }; state = nil
            status = (error as? CodexBridgeError)?.localizedDescription ?? "브리지 연결 실패 · 작업을 자동 전송하지 않았습니다"
        }
    }
    private func mutate(_ path: String, body: [String: Any]) async throws -> String {
        guard !busy else { throw CodexBridgeError.rejected("bridge_busy") }
        guard !hasUnknownDelivery else { throw CodexBridgeError.unknownDelivery }
        guard let token = key(endpoint), !endpoint.isEmpty else { throw CodexBridgeError.missingKey }
        let data = try JSONSerialization.data(withJSONObject: body)
        let pending = try JSONSerialization.data(withJSONObject: ["endpoint": endpoint, "path": path, "body": body])
        // At-most-once recovery retains user text locally until outcome is resolved.
        defaults.set(pending, forKey: prefix + "pending"); hasUnknownDelivery = true
        return try await deliver(path, data: data, token: token)
    }
    private func deliver(_ path: String, data: Data, token: String) async throws -> String {
        busy = true; defer { busy = false }
        do {
            let response = try await send(endpoint, token, path, data)
            guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                  object["accepted"] as? Bool == true, let id = object["taskId"] as? String else { throw CodexBridgeError.invalidResponse }
            selectedTaskID = id; defaults.set(id, forKey: prefix + "selected")
            defaults.removeObject(forKey: prefix + "pending"); hasUnknownDelivery = false
            lastDeliveryError = nil; defaults.removeObject(forKey: prefix + "deliveryError")
            status = "요청 전송됨 · 실제 결과는 작업 상태에서 확인하세요"; await refresh(); return id
        } catch {
            lastDeliveryError = (error as? CodexBridgeError)?.localizedDescription ?? "네트워크 오류로 접수 결과를 확인하지 못했습니다"
            defaults.set(lastDeliveryError, forKey: prefix + "deliveryError")
            status = "요청 결과 확인 필요 · 자동 중복 전송하지 않습니다"; throw error
        }
    }
    func retryPending() async {
        guard !busy, let pending = defaults.data(forKey: prefix + "pending"),
              let object = (try? JSONSerialization.jsonObject(with: pending)) as? [String: Any],
              object["endpoint"] as? String == endpoint, let path = object["path"] as? String,
              let body = object["body"] as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: body), let token = key(endpoint) else { return }
        do { _ = try await deliver(path, data: data, token: token) } catch { status = "이전 요청 미확인 · 원래 요청 ID를 유지하며 중복 작업을 만들지 않았습니다" }
    }
    /// Only the explicit native confirmation calls this. Does not retry or cancel PC work.
    func releaseUnconfirmedDelivery() {
        guard !busy, hasUnknownDelivery else { return }
        defaults.removeObject(forKey: prefix + "pending")
        defaults.removeObject(forKey: prefix + "deliveryError")
        hasUnknownDelivery = false; lastDeliveryError = nil
        status = "아이폰의 전송 보류를 해제했습니다 · PC 작업은 그대로 유지됩니다"
    }
    func message(_ text: String, requestID: String = UUID().uuidString) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 8192 else { throw CodexBridgeError.rejected("invalid_text") }
        var body: [String: Any] = ["text": text, "requestId": requestID]
        if let id = selectedTaskID { body["taskId"] = id }
        return try await mutate("/v1/message", body: body)
    }
    func stop(requestID: String = UUID().uuidString) async throws {
        guard let id = selectedTaskID else { throw CodexBridgeError.rejected("no_selected_task") }
        _ = try await mutate("/v1/stop", body: ["taskId": id, "requestId": requestID])
    }
    func decide(_ request: CodexApproval, approve: Bool, answers: [String: String] = [:]) async throws {
        guard let task = selected, task.id == request.taskId, task.pending.contains(where: { $0.id == request.id }),
              request.expiresAt > Date().timeIntervalSince1970 * 1000 else { throw CodexBridgeError.rejected("stale_request") }
        _ = try await mutate("/v1/decision", body: ["taskId": task.id, "approvalId": request.id, "decision": approve ? "accept" : "decline", "answers": answers, "requestId": UUID().uuidString])
    }
    var toolDefinitions: [[String: Any]] {
        guard voiceToolsEnabled, configured else { return [] }
        return CodexToolDescriptor.all.map(\.definition)
    }
    func executeTool(name: String, arguments: String, requestID: UUID) async -> String {
        guard voiceToolsEnabled, configured, !Task.isCancelled else { return "Codex 도구가 꺼져 있습니다." }
        do {
            guard arguments.utf8.count <= 9000, let obj = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] else { throw CodexBridgeError.invalidResponse }
            switch name {
            case "codex_message":
                guard obj.count == 1, let text = obj["text"] as? String else { throw CodexBridgeError.invalidResponse }
                let id = try await message(text, requestID: requestID.uuidString)
                return "Codex에 요청했습니다. 작업 ID \(id.prefix(4)). 작업은 계속 실행되며 나중에 진행 상황을 물을 수 있습니다. 승인은 휴대폰에서 확인하세요."
            case "codex_status":
                guard obj.isEmpty else { throw CodexBridgeError.invalidResponse }; await refresh()
                guard state?.online == true, let task = selected else { return "현재 작업 상태가 없습니다. Turbo IO의 Codex 화면에서 연결하고 작업을 선택하세요." }
                return "Codex：\(task.status)。\(String(task.answer.suffix(350)))" + (task.pending.isEmpty ? "" : "자세한 질문이나 승인 요청은 휴대폰에서 확인하세요.")
            case "codex_stop":
                guard obj.isEmpty else { throw CodexBridgeError.invalidResponse }; try await stop(requestID: requestID.uuidString)
                return "Codex 작업 중지를 요청했습니다. 최종 상태는 작업 화면에서 확인하세요."
            default: return "지원하지 않는 도구입니다. 아무 작업도 실행하지 않았습니다."
            }
        } catch { return "Codex 요청 성공 여부를 확인할 수 없습니다. 휴대폰에서 확인하세요. 자동 재시도나 승인하지 않습니다." }
    }
}
