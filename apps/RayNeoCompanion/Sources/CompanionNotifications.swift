import Foundation
import Combine

/// Ordinary notifications, pinned to the official iOS 1.0.2 business 21 contract.
/// Separate from ANCS payload collection, voice text, and suggestion/approval cards.
enum GlassesNotificationProtocol {
    static let business: UInt8 = 21
    static let companionAppID = "io.turboio.companion"
    static let phoneAppID = "com.apple.mobilephone"

    static func validAppID(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        return id.utf8.count <= 128 && parts.count >= 2 && parts.allSatisfy { !$0.isEmpty } &&
            id.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").contains($0) }
    }

    static func settings(_ draft: NotificationPreferences) throws -> Data {
        guard [5,10,15,20,30].contains(draft.displayTime), draft.sources.count <= 100, draft.sources.contains(where: { $0.id == phoneAppID }),
              Set(draft.sources.map(\.id)).count == draft.sources.count,
              draft.sources.allSatisfy({ validAppID($0.id) }) else { throw DeviceFeatureError.invalidPacket }
        // Official 0x4c57c8 branches past enabled entries; disabled app IDs form filterUID.
        // Incoming calls are additionally controlled by the phone row's enabled flag.
        return try DeviceBusinessWire.encode(type: 17, json: [
            "notification": draft.enabled,
            "callNotification": draft.sources.first(where: { $0.id == phoneAppID })?.allowed ?? true,
            "avoidDuplicate": false, "displayTime": draft.displayTime, "intervalTime": 2,
            "filterUID": draft.sources.filter { !$0.allowed }.map(\.id).sorted()
        ])
    }

    static func notification(uid: String, title: String, content: String, date: Date = Date()) throws -> Data {
        guard let value = Int64(uid), value > 0, value <= Int32.max, String(value) == uid,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 80, content.count <= 500,
              [title, content].allSatisfy({ !$0.unicodeScalars.contains { CharacterSet.controlCharacters.subtracting(.newlines).contains($0) } }),
              date.timeIntervalSince1970.isFinite else { throw DeviceFeatureError.invalidPacket }
        // Official dev button uses decimal-string UID, category 0, reply false,
        // added=1, and local DateTime.toIso8601String(), NOT epoch milliseconds.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return try DeviceBusinessWire.encode(type: 2, json: [
            "notificationUID": uid, "appId": companionAppID, "appName": "Turbo IO",
            "title": title, "subtitle": "", "content": content,
            "timestamp": formatter.string(from: date), "category": 0, "reply": false, "type": 1
        ])
    }

    static func stateLabel(_ raw: Int64) -> String {
        switch raw {
        case 0: return "대기 중 (읽음 상태 아님)"
        case 1: return "표시 중 또는 알림 간격 대기 (안경 확인 필요)"
        case 2: return "착용하지 않음"
        case 3: return "방해 금지"
        case 4: return "다른 안경 기능 사용 중"
        default: return "알 수 없는 상태 \(raw) (성공으로 처리하지 않음)"
        }
    }
}

struct NotificationSource: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var allowed: Bool
    var displayName: String {
        // Old installations retain the saved source names and all user choices.
        // Localize only unchanged built-in names when rendering them.
        let legacy: [String: (String, String)] = [
            GlassesNotificationProtocol.phoneAppID: ("\u{7535}\u{8BDD}\u{FF08}\u{542B}\u{6765}\u{7535}\u{FF09}", "전화 (수신 전화 포함)"),
            "com.apple.MobileSMS": ("\u{4FE1}\u{606F}", "메시지"),
            "com.apple.mobilemail": ("\u{90AE}\u{4EF6}", "메일"),
            "com.tencent.xin": ("\u{5FAE}\u{4FE1}", "WeChat")
        ]
        guard let item = legacy[id], name == item.0 else { return name }
        return item.1
    }
}

struct NotificationPreferences: Codable, Equatable {
    var enabled = false
    var displayTime = 5
    // This is a starter catalog, not an installed-app inventory or a deny-unknown policy.
    var sources: [NotificationSource] = [
        .init(id: GlassesNotificationProtocol.companionAppID, name: "Turbo IO", allowed: true),
        .init(id: GlassesNotificationProtocol.phoneAppID, name: "전화 (수신 전화 포함)", allowed: true),
        .init(id: "com.apple.MobileSMS", name: "메시지", allowed: true),
        .init(id: "com.apple.mobilemail", name: "메일", allowed: true),
        .init(id: "com.tencent.xin", name: "WeChat", allowed: true)
    ]
    init() {}
    private enum CodingKeys: String, CodingKey { case enabled, sources, displayTime }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        sources = try c.decode([NotificationSource].self, forKey: .sources)
        // The built-in source keeps its wire ID and user choice across a display-name change.
        for index in sources.indices where sources[index].id == GlassesNotificationProtocol.companionAppID {
            sources[index].name = "Turbo IO"
        }
        // Preserve existing source choices when loading pre-duration preferences.
        displayTime = try c.decodeIfPresent(Int.self, forKey: .displayTime) ?? 5
    }
}

@MainActor final class CompanionNotifications: ObservableObject {
    @Published private(set) var preferences: NotificationPreferences
    @Published private(set) var configurationStatus = "기기의 초안 · 안경 설정을 읽거나 변경하지 않았습니다"
    @Published private(set) var sourcesNeedApply = true
    @Published private(set) var reportedEnabled: Bool?
    @Published private(set) var ancsAvailable: Bool?
    @Published private(set) var availabilityStatus = "알림 공유 상태 미확인"
    @Published private(set) var testStatus = "전송 전 · 사용자 알림은 iOS 알림 센터를 거치지 않습니다"
    @Published private(set) var lastUID: String?
    @Published private(set) var operationStatus: String?
    @Published private(set) var awaitingState = false
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private let key = "companion.v1.notificationPreferences"
    private let device: () -> String?
    private let isBusy: () -> Bool
    private let transport: (UInt8, Data) throws -> Void
    private let timeout: UInt64
    private var currentDevice: String?
    private var submittedEnabled: Bool?
    private var lastDevice: String?
    private var stateWait: Task<Void, Never>?
    private var availabilityWait: Task<Void, Never>?
    private var availabilityGeneration = UUID()
    private var nextUID = Int64.random(in: 1...Int64(Int32.max - 1))

    init(defaults: UserDefaults, device: @escaping () -> String?, isBusy: @escaping () -> Bool,
         timeoutNanoseconds: UInt64 = 8_000_000_000,
         transport: @escaping (UInt8, Data) throws -> Void) {
        self.defaults = defaults; self.device = device; self.isBusy = isBusy
        self.transport = transport; timeout = timeoutNanoseconds
        if let data = defaults.data(forKey: key), data.count <= 65_536,
           let saved = try? JSONDecoder().decode(NotificationPreferences.self, from: data),
           (try? GlassesNotificationProtocol.settings(saved)) != nil,
           saved.sources.contains(where: { $0.id == GlassesNotificationProtocol.companionAppID }),
           saved.sources.contains(where: { $0.id == GlassesNotificationProtocol.phoneAppID }),
           saved.sources.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 40 && $0.name.rangeOfCharacter(from: .controlCharacters) == nil }) {
            preferences = saved
        } else { preferences = NotificationPreferences() }
        currentDevice = device()
    }
    deinit { stateWait?.cancel(); availabilityWait?.cancel() }
    var connected: Bool { device() != nil }
    var masterApplied: Bool { (reportedEnabled ?? submittedEnabled) == true }
    var canSend: Bool { connected && !isBusy() }
    var canTest: Bool {
        canSend && !awaitingState && preferences.enabled &&
            preferences.sources.first(where: { $0.id == GlassesNotificationProtocol.companionAppID })?.allowed == true
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: key) }
    }
    func setEnabled(_ enabled: Bool) {
        preferences.enabled = enabled; persist()
        configurationStatus = "전체 알림 초안 저장됨 · 적용 전"
        if canSend { applyMaster() }
    }
    func setDisplayTime(_ seconds: Int) {
        guard [5,10,15,20,30].contains(seconds) else { error = "이 버전의 테스트 범위를 벗어난 표시 시간입니다."; return }
        preferences.displayTime = seconds; persist(); sourcesNeedApply = true
        configurationStatus = "표시 시간 초안 저장됨 · 전체 알림 설정을 확인한 뒤 적용하세요"
    }
    func setAllowed(_ id: String, _ allowed: Bool) {
        guard let index = preferences.sources.firstIndex(where: { $0.id == id }) else { return }
        preferences.sources[index].allowed = allowed; persist()
        sourcesNeedApply = true
        configurationStatus = "앱별 알림 초안 변경됨 · 앱별 알림 설정 적용을 누르세요"
    }
    @discardableResult func addSource(name: String, id: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GlassesNotificationProtocol.validAppID(id), !name.isEmpty, name.count <= 40,
              name.rangeOfCharacter(from: .controlCharacters) == nil,
              preferences.sources.count < 100, !preferences.sources.contains(where: { $0.id == id }) else {
            error = "중복되지 않는 Bundle ID와 1~40자 이름을 입력하세요. 최대 100개 출처를 지원합니다."; return false
        }
        preferences.sources.append(.init(id: id, name: name, allowed: true)); persist()
        sourcesNeedApply = true
        configurationStatus = "새 알림 출처 초안 저장됨 · 앱별 알림 설정 적용을 누르세요"; error = nil; return true
    }
    func connectionChanged() {
        let next = device()
        guard next != currentDevice else { return }
        currentDevice = next; invalidateConnectionEvidence("연결이 바뀌었습니다. 수동 적용이 필요하며 안경 설정을 자동으로 덮어쓰지 않습니다")
    }
    func lostMessages() { invalidateConnectionEvidence("응답이 누락되어 상태를 확인할 수 없습니다. 다시 조회하거나 테스트하세요") }
    private func invalidateConnectionEvidence(_ reason: String) {
        stateWait?.cancel(); availabilityWait?.cancel(); availabilityGeneration = UUID()
        if lastUID != nil { testStatus = "\(reason) · 이전 요청 결과 미확인" }
        awaitingState = false; lastDevice = nil; operationStatus = nil
        submittedEnabled = nil; reportedEnabled = nil; ancsAvailable = nil
        sourcesNeedApply = true
        configurationStatus = reason; availabilityStatus = "알림 공유 상태 미확인"
    }
    private func check() throws -> String {
        connectionChanged()
        guard let id = device() else { throw DeviceFeatureError.disconnected }
        guard !isBusy() else { throw DeviceFeatureError.busy }
        return id
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); error = nil }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "요청 실패 · 안경 수신 미확인" }
    }
    func applyMaster() {
        perform {
            _ = try check()
            submittedEnabled = nil; reportedEnabled = nil
            try transport(21, DeviceBusinessWire.encode(type: 18, json: ["notification": preferences.enabled]))
            submittedEnabled = preferences.enabled
            configurationStatus = "전체 알림 전송됨 (\(preferences.enabled ? "켜짐" : "꺼짐")) · 앱별 설정은 이번에 전송하지 않았으며 안경 표시 미확인"
        }
    }
    /// Full replacement, explicitly confirmed in UI. No merge/readback contract is known.
    func applySources() {
        perform {
            _ = try check()
            submittedEnabled = nil; reportedEnabled = nil
            sourcesNeedApply = true
            try transport(21, GlassesNotificationProtocol.settings(preferences))
            submittedEnabled = preferences.enabled
            sourcesNeedApply = false
            configurationStatus = "앱별 및 전체 알림 설정 전송됨 · 항목별 응답은 없으므로 필터 동작을 안경에서 확인하세요"
        }
    }
    func queryAvailability() {
        perform {
            let id = try check()
            let packet = try DeviceBusinessWire.encode(type: 20, json: [:])
            availabilityWait?.cancel(); availabilityGeneration = UUID()
            let generation = availabilityGeneration
            ancsAvailable = nil; availabilityStatus = "조회 요청됨 · 안경 응답 대기 중"
            do { try transport(21, packet) }
            catch { availabilityStatus = "조회 요청 실패 · 상태 미확인"; throw error }
            availabilityWait = Task { [weak self, timeout] in
                do { try await Task.sleep(nanoseconds: timeout) } catch { return }
                guard let self, self.availabilityGeneration == generation, self.device() == id, self.ancsAvailable == nil else { return }
                self.availabilityStatus = "조회 시간 초과 · 현재 알림 공유 상태 미확인. 자동 재시도하지 않습니다"
            }
        }
    }
    /// Reusable future API entry; callers still obey connection, master and source policy.
    @discardableResult func send(title: String, content: String) -> String? {
        var sent: String?
        perform {
            let id = try check()
            guard preferences.enabled else { throw NotificationControlError.disabled }
            guard preferences.sources.first(where: { $0.id == GlassesNotificationProtocol.companionAppID })?.allowed == true else { throw NotificationControlError.sourceDenied }
            guard !awaitingState else { throw NotificationControlError.pending }
            guard (reportedEnabled ?? submittedEnabled) == true else {
                throw NotificationControlError.masterNotApplied
            }
            nextUID = nextUID >= Int32.max ? 1 : nextUID + 1
            let uid = String(nextUID)
            let packet = try GlassesNotificationProtocol.notification(uid: uid, title: title, content: content)
            // Register before transport so an immediate same-UID callback cannot be lost.
            lastUID = uid; lastDevice = id; awaitingState = true; operationStatus = nil
            testStatus = "SDK 전송 요청됨 · 같은 UID의 안경 응답을 최대 8초 기다립니다"
            do { try transport(21, packet) }
            catch { awaitingState = false; lastDevice = nil; testStatus = "전송 요청 실패 · 성공 아님"; throw error }
            sent = uid
            stateWait?.cancel()
            stateWait = Task { [weak self, timeout] in
                do { try await Task.sleep(nanoseconds: timeout) } catch { return }
                guard let self, self.device() == id, self.lastDevice == id, self.lastUID == uid, self.awaitingState else { return }
                self.awaitingState = false
                self.testStatus = "안경 응답 시간 초과 · 표시 미확인. 자동 재전송하지 않습니다"
            }
        }
        return sent
    }
    func receive(device id: String, wire: DeviceBusinessWire) {
        connectionChanged()
        guard id == device(), wire.bytes.isEmpty else { return }
        let json = wire.json
        if wire.type == 18, let value = DeviceBusinessWire.boolean(json, "notification") {
            reportedEnabled = value // Report only: no request ID, no source-filter ACK.
        } else if wire.type == 21, let available = DeviceBusinessWire.boolean(json, "available") {
            ancsAvailable = available; availabilityWait?.cancel()
            availabilityStatus = available ? "안경의 ANCS 사용 가능 (모든 알림 표시를 보장하지 않음)" : "안경의 ANCS 사용 불가 · Bluetooth 시스템 알림 공유 설정을 확인하세요"
        } else if [3, 4].contains(wire.type), id == lastDevice,
                  DeviceBusinessWire.identifier(json, "notificationUID") == lastUID {
            if wire.type == 3, let raw = DeviceBusinessWire.integer(json, "state") {
                awaitingState = false; stateWait?.cancel()
                testStatus = "같은 UID의 안경 응답: " + GlassesNotificationProtocol.stateLabel(raw)
            } else if wire.type == 4, let raw = DeviceBusinessWire.integer(json, "cmd") {
                operationStatus = "같은 UID의 작업 cmd=\(raw) · 의미 미검증. 도구를 실행하지 않습니다"
            }
        }
        // Type 1 ANCS may contain other apps' private text. Do not persist/log/forward it.
        // Type 19 is an app-category catalog, not a whitelist. Do not substitute it for 17.
    }
}

enum NotificationControlError: LocalizedError {
    case masterNotApplied, disabled, sourceDenied, pending
    var errorDescription: String? {
        switch self {
        case .masterNotApplied: return "현재 안경에 전체 알림 설정을 먼저 적용하세요."
        case .disabled: return "전체 알림이 꺼져 있어 전송하지 않았습니다."
        case .sourceDenied: return "Turbo IO 알림 출처가 꺼져 있어 전송하지 않았습니다."
        case .pending: return "이전 요청이 안경 응답을 기다립니다. 잠시 후 다시 시도하세요."
        }
    }
}
