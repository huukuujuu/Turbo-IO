import Foundation
import Network
import SwiftUI

/// Loopback only, intended for a trusted USB usbmux tunnel, not a LAN service.
@MainActor final class DisplayObserverServer: ObservableObject {
    static let shared = DisplayObserverServer()
    @Published private(set) var running = false
    @Published private(set) var status = "꺼짐 · 관찰 데이터를 내보내지 않습니다"
    @Published private(set) var token = ""
    private var listener: NWListener?
    private var clients: [UUID:NWConnection] = [:]
    private var expiry: Timer?
    let observation = DisplayObservation.shared
    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: 18765)
        do {
            let value = try NWListener(using: parameters)
            listener = value; token = UUID().uuidString.replacingOccurrences(of:"-",with:"")
            observation.reset(); observation.enabled = true; status = "시작 중"
            value.stateUpdateHandler = { [weak self, weak value] state in
                Task { @MainActor in
                guard let self, self.listener === value else { return }
                switch state {
                case .ready: self.running = true; self.status = "USB 관찰 켜짐 · 30분 후 자동 종료"
                case .failed: self.stop(); self.status = "인터페이스 시작 실패 · 네트워크 포트를 열지 않았습니다"
                default: break
                }
                }
            }
            value.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.listener != nil else { connection.cancel(); return }
                    self.accept(connection)
                }
            }
            value.start(queue:.main)
            expiry = Timer.scheduledTimer(withTimeInterval:1800,repeats:false) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        } catch { stop(); status = "관찰 인터페이스 사용 불가" }
    }
    func stop() {
        expiry?.invalidate(); expiry = nil
        listener?.cancel(); listener = nil
        for c in clients.values { c.cancel() }; clients.removeAll()
        observation.enabled = false; observation.includesText = false; observation.reset()
        token = ""; running = false; status = "관찰을 끄고 이번 데이터를 지웠습니다"
    }
    private func accept(_ connection: NWConnection) {
        guard clients.count < 8 else { connection.cancel(); return }
        let id = UUID(); clients[id] = connection
        connection.start(queue:.main)
        DispatchQueue.main.asyncAfter(deadline:.now()+4) { [weak self] in self?.close(id) }
        read(connection,id:id,buffer:Data())
    }
    private func close(_ id: UUID) { clients.removeValue(forKey:id)?.cancel() }
    private func read(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:4096) { [weak self] data, _, done, error in
            Task { @MainActor in
            guard let self, self.clients[id] != nil else { return }
            var all = buffer; if let data { all.append(data) }
            guard all.count <= 8192, error == nil else { self.close(id); return }
            if all.range(of:Data("\r\n\r\n".utf8)) != nil {
                let authorized = Self.authorized(all,token:self.token)
                let body = authorized ? (try? JSONSerialization.data(withJSONObject:self.observation.snapshot())) ?? Data("{}".utf8) : Data("{\"error\":\"unauthorized\"}".utf8)
                var response = Data("HTTP/1.1 \(authorized ? "200 OK" : "403 Forbidden")\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
                response.append(body)
                connection.send(content:response,completion:.contentProcessed { [weak self] _ in
                    Task { @MainActor in self?.close(id) }
                })
            } else if done { self.close(id) }
            else { self.read(connection,id:id,buffer:all) }
            }
        }
    }
    static func authorized(_ data: Data, token: String) -> Bool {
        guard token.count == 32, data.count <= 8192, let text = String(data:data,encoding:.utf8) else { return false }
        let lines = text.components(separatedBy:"\r\n")
        guard lines.first == "GET /snapshot HTTP/1.1", lines.last == "" else { return false }
        let headers = lines.dropFirst().filter { !$0.isEmpty }
        guard !headers.contains(where: { $0.lowercased().hasPrefix("origin:") || $0.lowercased().hasPrefix("transfer-encoding:") }) else { return false }
        let auth = headers.filter { $0.lowercased().hasPrefix("authorization:") }
        return auth.count == 1 && auth[0].dropFirst("authorization:".count).trimmingCharacters(in:.whitespaces) == "Bearer \(token)"
    }
}

struct DisplayObserverView: View {
    @ObservedObject private var server = DisplayObserverServer.shared
    @ObservedObject private var observation = DisplayObservation.shared
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Text("디스플레이 관찰 · USB").font(.title2.bold())
                Text("화면 상태를 읽기만 합니다. 미리보기는 안경 스크린샷이 아닙니다. 녹음, 모델 호출 또는 안경 화면 변경을 하지 않습니다.")
                Text(server.status).accessibilityIdentifier("display-observer-status")
                Toggle("이번에 전송한 텍스트 포함",isOn:$observation.includesText).accessibilityIdentifier("display-observer-text")
                Text("켜져 있는 동안 최대 80개 이벤트를 수집하며 텍스트를 로그나 디스크에 저장하지 않습니다. 끄면 캐시와 토큰을 지웁니다. 앱이 중지되면 PC에 연결 끊김으로 표시됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(server.running ? "관찰 인터페이스 끄기" : "USB 관찰 인터페이스 켜기") { server.running ? server.stop() : server.start() }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("display-observer-toggle")
                if server.running {
                    Text("PC 관찰 페이지에 일회용 토큰 입력:").font(.caption)
                    Text(server.token).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                        .accessibilityIdentifier("display-observer-token")
                    Button("토큰 복사") { UIPasteboard.general.setItems([["public.utf8-plain-text":server.token]],options:[.localOnly:true,.expirationDate:Date().addingTimeInterval(120)]) }
                    Text("USB 전달 포트 18765 · 로컬 루프백으로만 접근 · 탈옥 불필요")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }.navigationTitle("디스플레이 관찰").navigationBarTitleDisplayMode(.inline)
    }
}
