import Foundation
import Combine
import Security
import RayNeoDisplay

enum QWeatherError: LocalizedError {
    case configuration, key, response, stale, network, http(Int)
    var errorDescription: String? {
        switch self {
        case .configuration: return "QWeather 전용 호스트(경로 제외), 지역, 소수점 둘째 자리 좌표를 입력하세요."
        case .key: return "이 호스트의 QWeather API 키를 저장하세요. 다른 서비스 키를 재사용하지 않습니다."
        case .response: return "QWeather 응답의 필드, 단위 또는 출처 정보가 불완전해 전송하지 않았습니다."
        case .stale: return "날씨 조회 결과가 만료됐습니다. 다시 조회하세요. 응답 시간과 관측 시간은 다릅니다."
        case .network: return "QWeather 요청 실패 또는 시간 초과 · 전송하지 않았습니다. 자동 우회나 리디렉션은 하지 않습니다."
        case .http(let code): return "QWeather HTTP \(code) · 서비스 설정을 확인하세요."
        }
    }
}

struct QWeatherSnapshot: Equatable {
    let temperature: Double
    let condition: String
    let code: Int
    let fetchedAt: Date
    let attributions: [String]
    var lensTemperature: Int { Int(temperature.rounded()) }
    // v1 has no observation timestamp. This is explicitly a local receipt-age policy.
    func isFresh(_ now: Date) -> Bool { (0...600).contains(now.timeIntervalSince(fetchedAt)) }
}

struct QWeatherConfiguration: Codable, Equatable {
    var host = ""
    var location = "Beijing"
    var latitude = "39.92"
    var longitude = "116.41"
    var enabled = true
    var verifiedIcons: [String: Int] = [:]
    static func validHost(_ input: String) -> Bool {
        input.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*\.qweatherapi\.com$"#, options:.regularExpression) != nil && input.count <= 253
    }
    func validate() throws {
        func coordinate(_ input: String, limit: Double) -> Bool {
            input.range(of:#"^-?[0-9]{1,3}(\.[0-9]{1,2})?$"#,options:.regularExpression) != nil && Double(input).map { abs($0) <= limit } == true
        }
        guard Self.validHost(host), !location.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              location.utf8.count <= 80, !location.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains),
              coordinate(latitude,limit:90), coordinate(longitude,limit:180), verifiedIcons.count <= 100,
              verifiedIcons.allSatisfy({ Int($0.key) != nil && (0...999).contains($0.value) }) else { throw QWeatherError.configuration }
    }
}

enum QWeatherVault {
    private static func query(_ host: String) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"io.turboio.companion.qweather",kSecAttrAccount as String:host]
    }
    static func read(_ host: String) -> String? {
        guard QWeatherConfiguration.validHost(host) else { return nil }
        var q = query(host); q[kSecReturnData as String] = true
        var value: CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary,&value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    static func save(_ key: String, host: String) throws {
        guard QWeatherConfiguration.validHost(host), !key.isEmpty, key.count <= 512,
              key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw QWeatherError.key }
        let attrs: [String:Any] = [kSecValueData as String:Data(key.utf8),kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let result = SecItemUpdate(query(host) as CFDictionary,attrs as CFDictionary)
        if result == errSecItemNotFound {
            let insert = query(host).merging(attrs,uniquingKeysWith:{ _,new in new })
            guard SecItemAdd(insert as CFDictionary,nil) == errSecSuccess else { throw QWeatherError.key }
        } else if result != errSecSuccess { throw QWeatherError.key }
    }
}

private final class QWeatherNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum QWeatherClient {
    static let limit = 262_144
    static func request(_ c: QWeatherConfiguration, key: String) throws -> URLRequest {
        try c.validate()
        guard !key.isEmpty, key.count <= 512, key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw QWeatherError.key }
        var u = URLComponents(); u.scheme = "https"; u.host = c.host
        u.path = "/weather/v1/current/\(c.latitude)/\(c.longitude)"; u.queryItems = [URLQueryItem(name:"lang",value:"zh")]
        guard let url = u.url else { throw QWeatherError.configuration }
        var r = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:20)
        r.setValue(key,forHTTPHeaderField:"X-QW-Api-Key"); r.setValue("application/json",forHTTPHeaderField:"Accept")
        return r
    }
    static func decode(_ data: Data, now: Date) throws -> QWeatherSnapshot {
        struct Response: Decodable {
            struct Temperature: Decodable { let value: Double; let unit: String }
            struct Condition: Decodable { let text: String; let code: String }
            struct Metadata: Decodable { let attributions: [String] }
            let temperature: Temperature; let condition: Condition; let metadata: Metadata
        }
        guard data.count <= limit, let r = try? JSONDecoder().decode(Response.self,from:data),
              r.temperature.unit == "°C", r.temperature.value.isFinite, (-80...60).contains(r.temperature.value),
              let code = Int(r.condition.code), (0...999).contains(code), !r.condition.text.isEmpty, r.condition.text.utf8.count <= 160,
              !r.metadata.attributions.isEmpty, r.metadata.attributions.count <= 10,
              r.metadata.attributions.allSatisfy({ $0.utf8.count <= 1024 }) else { throw QWeatherError.response }
        return QWeatherSnapshot(temperature:r.temperature.value,condition:r.condition.text,code:code,fetchedAt:now,attributions:r.metadata.attributions)
    }
    static func fetch(_ c: QWeatherConfiguration, key: String) async throws -> QWeatherSnapshot {
        let request = try request(c,key:key)
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForResource = 25
        let session = URLSession(configuration:config,delegate:QWeatherNoRedirect(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes,response) = try await session.bytes(for:request)
            guard let http = response as? HTTPURLResponse else { throw QWeatherError.response }
            guard http.statusCode == 200 else { throw QWeatherError.http(http.statusCode) }
            guard response.expectedContentLength <= limit else { throw QWeatherError.response }
            var data = Data()
            for try await byte in bytes { try Task.checkCancellation(); guard data.count < limit else { throw QWeatherError.response }; data.append(byte) }
            return try decode(data,now:Date())
        } catch let e as QWeatherError { throw e }
        catch { throw QWeatherError.network }
    }
    static func dashboardWire(_ s: QWeatherSnapshot, configuration: QWeatherConfiguration, icon: Int, now: Date) throws -> Data {
        try configuration.validate()
        guard s.isFresh(now), (0...999).contains(icon) else { throw QWeatherError.stale }
        let msg = try WeatherJSONCodec().encodeCurrentWeatherUpdate(.init(location:configuration.location,
            temperatureRaw:Int64(s.lensTemperature),iconRaw:Int64(icon),timestampRaw:String(Int64(now.timeIntervalSince1970))))
        let json = try JSONSerialization.jsonObject(with:msg.payload) as! [String:Any]
        return try DeviceBusinessWire.encode(type:UInt32(msg.type),json:json)
    }
}

@MainActor final class QWeatherDashboard: ObservableObject {
    @Published private(set) var configuration: QWeatherConfiguration
    @Published private(set) var snapshot: QWeatherSnapshot?
    @Published private(set) var status = "대시보드 날씨: QWeather 호스트와 API 키 설정 필요"
    @Published private(set) var reply = "대시보드 날씨 전송 전"
    @Published private(set) var busy = false
    private let defaults: UserDefaults
    private let device: () -> String?
    private let occupied: () -> Bool
    private let readKey: (String) -> String?
    private let fetch: (QWeatherConfiguration,String) async throws -> QWeatherSnapshot
    private let send: (Data) throws -> Void
    private let now: () -> Date
    private var connected: String?
    private var epoch = UUID(), pending = false
    private var worker: Task<Void,Never>?
    private var cachedConfig: QWeatherConfiguration?
    private var lastFetch: Date?, awaiting: Date?
    private let storage = "companion.v1.qweatherDashboard"
    init(defaults: UserDefaults, device: @escaping () -> String?, occupied: @escaping () -> Bool,
         readKey: @escaping (String)->String? = QWeatherVault.read,
         fetch: @escaping (QWeatherConfiguration,String) async throws -> QWeatherSnapshot = QWeatherClient.fetch,
         now: @escaping () -> Date = Date.init, send: @escaping (Data)throws->Void) {
        self.defaults = defaults; self.device = device; self.occupied = occupied; self.readKey = readKey; self.fetch = fetch; self.send = send; self.now = now
        if let data = defaults.data(forKey:storage), let value = try? JSONDecoder().decode(QWeatherConfiguration.self,from:data), (try? value.validate()) != nil { configuration = value }
        else { configuration = QWeatherConfiguration() }
    }
    func save(_ value: QWeatherConfiguration, key: String) {
        do {
            try value.validate()
            if !key.isEmpty { try QWeatherVault.save(key,host:value.host) }
            configuration = value; defaults.set(try JSONEncoder().encode(value),forKey:storage)
            cancel(); snapshot = nil; cachedConfig = nil; pending = true; tick()
        } catch { status = (error as? QWeatherError)?.localizedDescription ?? "설정 저장 실패" }
    }
    func retry() { cancel(); pending = true; tick() }
    private func cancel() { epoch = UUID(); worker?.cancel(); worker = nil; busy = false; awaiting = nil; reply = "연결 또는 설정이 바뀌어 이전 응답을 사용하지 않습니다." }
    func tick() {
        let d = device()
        if d != connected { cancel(); connected = d; pending = d != nil }
        if let since = awaiting, now().timeIntervalSince(since) >= 8 { awaiting = nil; reply = "8초 안에 날씨 응답을 받지 못했습니다. 자동 재전송하지 않으며 실제 표시 여부는 안경에서 확인하세요." }
        guard configuration.enabled else { status = "대시보드 자동 날씨 꺼짐"; return }
        guard let d else { status = "안경 연결 인증 대기 중 · 조회나 전송 전"; return }
        guard pending, worker == nil else { return }
        guard !occupied() else { status = "음성 대화, 녹음 또는 프롬프터 종료 후 대시보드를 갱신합니다."; return }
        guard (try? configuration.validate()) != nil else { pending = false; status = QWeatherError.configuration.localizedDescription; return }
        guard let key = readKey(configuration.host) else { pending = false; status = QWeatherError.key.localizedDescription; return }
        let cache = cachedConfig == configuration && snapshot?.isFresh(now()) == true ? snapshot : nil
        if cache == nil, let lastFetch, now().timeIntervalSince(lastFetch) < 60 { status = "조회 간격 제한 · 60초 후 다시 조회하세요."; return }
        let token = epoch, c = configuration; pending = false; busy = true
        if cache == nil { lastFetch = now() }
        status = "\(c.location) 실시간 날씨를 조회하여 대시보드 홈에 표시합니다."
        worker = Task { [weak self] in
            guard let self else { return }
            defer { if self.epoch == token { self.worker = nil; self.busy = false } }
            do {
                let s: QWeatherSnapshot
                if let cache { s = cache } else { s = try await self.fetch(c,key) }
                guard !Task.isCancelled, self.epoch == token, self.device() == d, self.configuration == c else { return }
                guard s.isFresh(self.now()) else { throw QWeatherError.stale }
                self.snapshot = s; self.cachedConfig = c
                guard let icon = c.verifiedIcons[String(s.code)] else { self.status = "\(c.location) \(s.lensTemperature)°C · \(s.condition) 조회됨 · 아이콘 테스트 필요 \(s.code) · 자동 전송 전"; return }
                guard !self.occupied() else { self.pending = true; self.status = "날씨 조회됨 · 안경 사용 종료 대기 중"; return }
                try self.submit(s,icon:icon,candidate:false)
            } catch { if self.epoch == token, !Task.isCancelled { self.status = (error as? QWeatherError)?.localizedDescription ?? "날씨 조회 또는 전송 실패" } }
        }
    }
    private func submit(_ s: QWeatherSnapshot, icon: Int, candidate: Bool) throws {
        guard device() != nil, device() == connected, !occupied(), cachedConfig == configuration else { throw DeviceFeatureError.disconnected }
        let bytes = try QWeatherClient.dashboardWire(s,configuration:configuration,icon:icon,now:now())
        awaiting = now(); reply = "current_weather_update 전송됨 · type19 응답 대기 중"
        do { try send(bytes) } catch { awaiting = nil; reply = "SDK 전송 실패 · 안경 수신 미확인"; throw error }
        status = "대시보드 전송됨: \(configuration.location) \(s.lensTemperature)°C · \(s.condition) · 아이콘 \(icon)\(candidate ? " · 확인할 아이콘" : " · 직접 확인한 아이콘"). 날씨 카드 갱신과는 별개입니다."
    }
    func testCandidate() {
        guard !busy, awaiting == nil, let s = snapshot else { return }
        do { try submit(s,icon:s.code,candidate:true) } catch { status = "아이콘 테스트 전송 불가 · 연결, 데이터 유효 시간 또는 안경 사용 상태를 확인하세요." }
    }
    func confirmDisplayedIcon() {
        guard let s = snapshot, s.isFresh(now()), cachedConfig == configuration else { return }
        configuration.verifiedIcons[String(s.code)] = s.code
        defaults.set(try? JSONEncoder().encode(configuration),forKey:storage)
        cachedConfig = configuration
        status = "사용자 확인 저장됨: 날씨 코드 \(s.code)의 동일 번호 아이콘 · 다음 인증 연결부터 해당 유형을 자동 전송할 수 있습니다."
    }
    func receive(device d: String, wire: DeviceBusinessWire) {
        guard d == device(), d == connected, wire.type == 19, wire.bytes.isEmpty,
              wire.json["cmd"] as? String == "current_weather_update", awaiting != nil,
              let p = wire.json["payload"] as? [String:Any], let value = DeviceBusinessWire.integer(p,"value") else { return }
        awaiting = nil
        reply = "안경 응답 current_weather_update value=\(value)\(value == 0 ? " (프로토콜 성공 값)" : "") · 응답에는 요청 ID가 없으므로 실제 안경 내용을 확인하세요."
    }
}
