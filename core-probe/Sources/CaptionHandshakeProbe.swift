#if COMPANION_DEVICE
import Foundation
import UIKit

/// Explicit development-launch experiment. No decoding, storage, or cloud API.
/// The start response shape is experimental; audio arrival is the acceptance gate.
final class CaptionHandshakeProbe {
    var enabled = false
    var responseCode = 1 // Experimental variants; never inferred as a verified contract.
    var recorderControl = false
    var send: ((String, UInt8, Data) throws -> Void)?
    var log: ((String) -> Void)?
    private var sid: String?
    private var device: String?
    private var activeBusiness: UInt8?
    private var timer: Timer?
    private var packets = 0
    private var bytes = 0
    private var background: NSObjectProtocol?
    init() {
        background = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in self?.stop(sendStop: true) }
    }
    deinit { timer?.invalidate(); if let background { NotificationCenter.default.removeObserver(background) } }
    func receive(device source: String, business: UInt8, payload: Data) {
        guard enabled, [19,23].contains(business), let wire = try? DeviceBusinessWire(payload) else { return }
        if wire.type == 1 {
            guard sid == nil, let incoming = DeviceBusinessWire.identifier(wire.json, "sid"),
                  DeviceBusinessWire.integer(wire.json, "code") == 1 else { return }
            sid = incoming; device = source; activeBusiness = business; packets = 0; bytes = 0
            do {
                var reply: [String: Any] = ["sid": incoming, "code": responseCode]
                if recorderControl { reply = ["sid": incoming, "rc": 1] }
                else if let settings = wire.json["settings"] as? [String: Any] { reply["settings"] = settings }
                try send?(source, business, DeviceBusinessWire.encode(type: 2, json: reply))
                log?("자막 연결 실험: business=\(business) type2 \(recorderControl ? "rc=1" : "code=\(responseCode)") 제출 · 8초 동안 오디오 길이만 확인 · 저장·업로드 없음")
                timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in self?.stop(sendStop: true) }
            } catch { log?("자막 연결 실험: 응답 제출 실패"); stop(sendStop: true) }
            return
        }
        guard device == source, activeBusiness == business, let sid else { return }
        if let incoming = wire.json["sid"] as? String, incoming != sid { return }
        if wire.type == 4 {
            packets += 1; bytes += wire.bytes.count
            if packets <= 3 || packets % 50 == 0 {
                log?("자막 연결 실험: business=\(business) audioPackets=\(packets) audioBytes=\(wire.bytes.count) totalBytes=\(bytes) · 본문 미기록")
            }
        } else if wire.type == 3 {
            log?("자막 연결 실험: 안경 종료 요청 수신")
            stop(sendStop: false)
        }
    }
    private func stop(sendStop: Bool) {
        timer?.invalidate(); timer = nil
        guard let sid, let device, let business = activeBusiness else { return }
        self.sid = nil; self.device = nil; activeBusiness = nil
        if sendStop {
            do { try send?(device, business, DeviceBusinessWire.encode(type: 3, json: ["sid": sid, "reason_code": 10, "text": ""])) }
            catch { log?("자막 연결 실험: 종료 제출 실패 · 안경에서 직접 종료 필요") }
        }
        log?("자막 연결 실험 종료 · packets=\(packets) bytes=\(bytes) · 실제 안경 종료는 별도 확인")
    }
}
#endif
