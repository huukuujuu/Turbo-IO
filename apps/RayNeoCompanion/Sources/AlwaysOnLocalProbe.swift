import Foundation
import Combine
import UIKit
import SwiftUI

/// Experimental iOS 1.0.2 LifeLog commands. Not the ordinary recording protocol.
enum AlwaysOnWire {
    static func launcher(_ command: String, enabled: Bool) throws -> Data {
        guard ["life_log_guide", "life_log_switch"].contains(command) else { throw DeviceFeatureError.invalidPacket }
        return try DeviceBusinessWire.encode(type: 20, json: ["cmd": command,
            "payload": ["value": enabled ? 1 : 0, "mode": 0,
                        "data": command == "life_log_switch" && enabled ? "{\"delay\":2}" : ""]])
    }
    static func start(_ id: String) throws -> Data {
        guard DeviceBusinessWire.identifier(["taskId": id], "taskId") != nil else { throw DeviceFeatureError.invalidPacket }
        return try DeviceBusinessWire.encode(type: 162, json: ["taskId": id, "idleTimeoutSec": 30])
    }
    static func exit() throws -> Data { try DeviceBusinessWire.encode(type: 166, json: ["rc": 2]) }
    static func page(_ visible: Bool) throws -> Data { try DeviceBusinessWire.encode(type: 168, json: ["inRealtimePage": visible]) }
    static func batchSummary(_ wire: DeviceBusinessWire) -> (frames: Int, unusedBytes: Int) {
        let keys = ["frameCount", "mode", "vpuMask", "vadMask"]
        guard keys.contains(where: { wire.json[$0] != nil }) else { return (wire.bytes.isEmpty ? 0 : 1, 0) }
        let available = wire.bytes.count / 240
        let declared = DeviceBusinessWire.integer(wire.json, "frameCount") ?? Int64(available)
        let frames = Int(min(31, min(Int64(available), max(0, declared))))
        return (frames, wire.bytes.count - frames * 240)
    }
}

/// Small bounded diagnostic capture: original length-prefixed envelopes, not a playable .opus claim.
@MainActor final class AlwaysOnLocalProbe: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var pendingStop: Bool
    @Published private(set) var status = "시작 전 · 녹음 및 업로드 없음"
    @Published private(set) var packetCount = 0
    @Published private(set) var audioBytes = 0
    @Published private(set) var receivedPackets = 0
    @Published private(set) var receivedAudioBytes = 0
    @Published private(set) var droppedPackets = 0
    @Published private(set) var droppedAudioBytes = 0
    @Published private(set) var tailPackets = 0
    @Published private(set) var frameCount = 0
    @Published private(set) var unusedBytes = 0
    @Published private(set) var remaining = 0
    @Published private(set) var events: [String] = []
    @Published private(set) var directory: URL?
    @Published private(set) var error: String?
    @Published private(set) var stopResultAcknowledged = false
    private let defaults: UserDefaults
    private let root: URL
    private let device: () -> String?
    private let available: () -> Bool
    private let send: (UInt8, Data) throws -> Void
    private let suspendVoice: () -> Void
    private let now: () -> TimeInterval
    private let scheduleTimers: Bool
    private var target: String?
    private var taskID = ""
    private var a2Sent = false
    private var offObserved = false
    private var stopAt: TimeInterval?
    private var lastStopRequest: TimeInterval?
    private var deadline: TimeInterval = 0
    private var acceptingAudio = false
    private var dropReasons: [String: Int] = [:]
    private var saveDeadline: TimeInterval { min(deadline + 5, stopAt.map { $0 + 5 } ?? deadline + 5) }
    private var lastAudio: TimeInterval = 0
    private var file: FileHandle?
    private var storedBytes = 0
    private var timer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let pendingKey = "companion.alwaysOn.localProbe.pendingDevice"
    var occupied: Bool { active || pendingStop }
    var canStart: Bool { device() != nil && available() && !occupied }
    var canConfirmPhysicalStop: Bool {
        pendingStop && !active && stopResultAcknowledged && target != nil && device() == target
    }
    init(defaults: UserDefaults, root: URL, device: @escaping () -> String?, available: @escaping () -> Bool,
         suspendVoice: @escaping () -> Void, send: @escaping (UInt8, Data) throws -> Void,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, scheduleTimers: Bool = true) {
        self.defaults = defaults; self.root = root; self.device = device; self.available = available
        self.suspendVoice = suspendVoice; self.send = send
        self.now = now; self.scheduleTimers = scheduleTimers
        target = defaults.string(forKey: pendingKey); pendingStop = target != nil
        if pendingStop { status = "이전 중지가 확인되지 않았습니다. 같은 안경을 연결하고 중지 재전송을 누르세요. 자동으로 시작하지 않습니다." }
    }
    private func note(_ text: String) {
        events.append("\(Date().formatted(date: .omitted, time: .standard)) \(text)")
        events = Array(events.suffix(80))
    }
    func start() {
        guard canStart, let id = device() else { error = "안경을 연결하고 음성 대화, 녹음, 프롬프터를 종료하세요. 확인되지 않은 이전 중지를 먼저 처리하세요."; return }
        do {
            let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let path = dir.appendingPathComponent("envelopes.rnp")
            try Data().write(to: path, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
            file = try FileHandle(forWritingTo: path); directory = dir
        } catch { self.error = "로컬 파일을 준비할 수 없어 시작하지 않았습니다."; return }
        suspendVoice()
        target = id; taskID = UUID().uuidString; a2Sent = false; offObserved = false; stopAt = nil
        lastStopRequest = nil; stopResultAcknowledged = false
        packetCount = 0; audioBytes = 0; frameCount = 0; unusedBytes = 0; storedBytes = 0; events = []; error = nil
        receivedPackets = 0; receivedAudioBytes = 0; droppedPackets = 0; droppedAudioBytes = 0; tailPackets = 0
        dropReasons = [:]; acceptingAudio = true
        active = true; pendingStop = true; defaults.set(id, forKey: pendingKey)
        deadline = now() + 25; lastAudio = 0; remaining = 25
        if scheduleTimers {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "LifeLogBoundedStop") { [weak self] in
            Task { @MainActor in self?.stop(reason: "백그라운드 실행 시간 만료"); self?.finishCapture() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        }
        do {
            try send(15, AlwaysOnWire.launcher("life_log_guide", enabled: true)); note("설정 전송 준비됨 (녹음 시작 확인 아님)")
            try send(15, AlwaysOnWire.launcher("life_log_switch", enabled: true)); note("일상 기록 켜기 요청 전송")
            status = "안경 상태 / A1 대기 중 · 25초에 중지 요청, 30초까지 남은 패킷 수신"
        } catch { acceptingAudio = false; self.error = "시작 요청 실패 · 끄기 요청을 시도합니다."; stop(reason: "시작 실패") }
    }
    func stop(reason: String = "수동 중지") {
        guard pendingStop || active else { return }
        if stopAt == nil { stopAt = now(); note("중지: \(reason)") }
        remaining = active ? max(0, Int(ceil(saveDeadline - now()))) : 0
        status = "중지 요청됨 · 남은 패킷 수신 및 꺼짐 상태 대기 중"
        stopResultAcknowledged = false; lastStopRequest = nil
        guard let target, device() == target else { status = "연결 중단 · 중지 미확인. 같은 안경에 다시 연결한 뒤 중지 요청을 재전송하세요"; return }
        lastStopRequest = now()
        // Attempt each stop independently: an A6 failure must not suppress switch OFF.
        for (business, packet) in [(UInt8(13), try? AlwaysOnWire.exit()), (15, try? AlwaysOnWire.launcher("life_log_switch", enabled: false)),
                                   (15, try? AlwaysOnWire.launcher("life_log_guide", enabled: false))] {
            do { if let packet { try send(business, packet) } } catch { self.error = "일부 중지 명령을 전송하지 못했습니다. 안경에서 중지됐는지 확인하세요." }
        }
        if !active { status = "중지 요청 재전송됨 · 안경 꺼짐 대기 중. 녹음은 재개하지 않았습니다" }
    }
    func connectionChanged() {
        if device() != target { acceptingAudio = false; stopResultAcknowledged = false; lastStopRequest = nil }
        if active, device() != target { stop(reason: "연결 변경") }
    }
    /// Explicit lens inspection, not a protocol-confirmed OFF claim. No recording or packet send.
    func confirmPhysicalStop() {
        guard canConfirmPhysicalStop else { return }
        let report: [String: Any] = ["confirmedAt": ISO8601DateFormatter().string(from: Date()),
            "source": "user-observed-glasses-off-after-stop-result", "protocolOffObserved": offObserved,
            "stopResultAcknowledged": true, "events": events]
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: root.appendingPathComponent("stop-confirmation-\(UUID().uuidString).json"),
                           options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { self.error = "수동 중지 확인을 저장하지 못했습니다. 확인 대기 상태를 유지합니다."; return }
        pendingStop = false; defaults.removeObject(forKey: pendingKey)
        status = "사용자가 안경 꺼짐을 확인하여 테스트를 종료했습니다 (프로토콜 OFF 상태 수신 전)"
        note(status)
    }
    func lostMessages() {
        guard active else { return }; acceptingAudio = false
        error = "수신 패킷이 누락됐습니다. 원본은 유지하지만 완전한 녹음으로 표시하지 않습니다."; stop(reason: "불완전한 수신")
    }
    func receive(device id: String, business: UInt8, packet: Data) {
        guard target == id, device() == id, active || pendingStop else { return }
        do {
            let wire = try DeviceBusinessWire(packet)
            if business == 15 {
                guard let cmd = wire.json["cmd"] as? String, cmd.hasPrefix("life_log_"),
                      let p = wire.json["payload"] as? [String: Any] else { return }
                let value = DeviceBusinessWire.integer(p, "value")
                note("\(cmd) value=\(value.map(String.init) ?? "기본값") mode=\(DeviceBusinessWire.integer(p, "mode").map(String.init) ?? "기본값")")
                if cmd == "life_log_switch_result", value == 0,
                   let request = lastStopRequest, now() - request >= 0, now() - request <= 10 {
                    stopResultAcknowledged = true
                    if !active { status = "설정 성공 응답을 받았습니다. 안경에서 꺼짐을 직접 확인한 뒤 완료하세요" }
                }
                if cmd == "life_log_switch", value == 0, stopAt != nil {
                    offObserved = true
                    if !active { pendingStop = false; defaults.removeObject(forKey: pendingKey); status = "꺼짐 상태 수신됨 · 녹음 재개 안 함" }
                }
                if cmd == "life_log_switch_result", let value, value != 0, stopAt == nil {
                    error = [1: "안경의 마이크 권한이 없습니다", 2: "안경 다리를 펴세요", 3: "안경 배터리가 부족합니다"][Int(value)] ?? "안경이 일상 기록 설정을 거부했습니다. 결과 코드 \(value)"
                    stop(reason: "안경에서 거부함")
                }
                return
            }
            guard business == 13, (161...168).contains(wire.type) else { return }
            if wire.type == 161 {
                note("A1 호출 수신됨")
                guard active, stopAt == nil, !a2Sent, now() < deadline else { return }
                a2Sent = true
                try send(13, AlwaysOnWire.start(taskID)); try send(13, AlwaysOnWire.page(false))
                note("A2 오디오 수집 / A8 화면 전송"); status = "안경 호출에 응답했습니다. 오디오 수신 대기 중"
            } else if wire.type == 163 || wire.type == 164 {
                let now = now()
                receivedPackets += 1; receivedAudioBytes += wire.bytes.count
                var saved = false
                var dropReason = "저장 실패"
                defer {
                    if !saved {
                        droppedPackets += 1; droppedAudioBytes += wire.bytes.count
                        dropReasons[dropReason, default: 0] += 1
                        if droppedPackets <= 3 || droppedPackets % 50 == 0 {
                            note("오디오 저장 안 됨: \(dropReason) · 이번 패킷 \(wire.bytes.count)바이트 · 누적 폐기 \(droppedPackets)패킷")
                        }
                    }
                }
                lastAudio = now
                if stopAt != nil { stopResultAcknowledged = false }
                guard active, acceptingAudio else { dropReason = "수신 종료 또는 오류로 중단됨"; return }
                guard now < saveDeadline else { dropReason = "수신 제한 시간 초과"; return }
                guard a2Sent else { dropReason = "A2 응답 전"; return }
                guard let incoming = DeviceBusinessWire.identifier(wire.json, "taskId") else {
                    dropReason = "유효한 taskId 없음"; return
                }
                guard incoming == taskID else { dropReason = "다른 taskId"; return }
                guard storedBytes + packet.count + 4 <= 8 * 1_024 * 1_024, packetCount < 4096 else { throw DeviceFeatureError.storageLimit }
                var length = UInt32(packet.count).littleEndian
                let prefix = withUnsafeBytes(of: &length) { Data($0) }
                guard let file else { throw DeviceFeatureError.invalidPacket }
                try file.write(contentsOf: prefix + packet)
                storedBytes += packet.count + 4; packetCount += 1; audioBytes += wire.bytes.count
                saved = true
                if stopAt != nil || now >= deadline { tailPackets += 1 }
                let summary = AlwaysOnWire.batchSummary(wire)
                frameCount += summary.frames; unusedBytes += summary.unusedBytes
                if packetCount == 1 || packetCount % 50 == 0 { note("A\(wire.type - 160) 패킷 \(packetCount) · 누적 오디오 \(audioBytes)바이트") }
                status = stopAt == nil ? "오디오가 기기에 저장됐습니다. 디코딩 가능 여부와 완전성은 확인 전입니다" : "중지 요청됨 · 남은 패킷 저장 완료, 종료 대기 중"
            } else if wire.type == 165 { note("A5 종료 수신 rc=\(DeviceBusinessWire.integer(wire.json, "rc").map(String.init) ?? "기본값")"); if stopAt == nil { stop(reason: "안경에서 종료함") } }
        } catch { acceptingAudio = false; self.error = "일상 기록 프로토콜 또는 파일 저장 오류입니다. 수신한 원본을 유지하고 중지합니다."; stop(reason: "수신 오류") }
    }
    func tick() {
        guard active else { return }
        let now = now()
        if stopAt == nil { remaining = max(0, Int(ceil(deadline - now))); if now >= deadline { stop(reason: "25초 제한") } }
        if stopAt != nil { remaining = max(0, Int(ceil(saveDeadline - now))) }
        if now >= saveDeadline { finishCapture() }
    }
    private func finishCapture() {
        guard active else { return }
        timer?.invalidate(); timer = nil; active = false; acceptingAudio = false; remaining = 0
        let quiet = lastAudio == 0 || now() - lastAudio >= 3
        if offObserved && quiet { pendingStop = false; defaults.removeObject(forKey: pendingKey) }
        status = pendingStop ? "로컬 저장을 중지했습니다. 안경 중지를 확인하지 못했으므로 중지 요청을 다시 보내고 안경을 확인하세요" : "꺼짐 상태를 받았고 새 오디오가 없습니다. 로컬 테스트를 종료했습니다"
        if pendingStop && stopResultAcknowledged { status = "설정 성공 응답을 받았습니다. 안경에서 꺼짐을 직접 확인한 뒤 완료하세요" }
        note(status)
        do {
            try file?.synchronize(); try file?.close(); file = nil
            if let directory {
                let data = try JSONSerialization.data(withJSONObject: ["createdAt": ISO8601DateFormatter().string(from: Date()),
                    "taskId": taskID, "packets": packetCount, "audioBytes": audioBytes, "frames": frameCount,
                    "unusedBytes": unusedBytes, "offObserved": offObserved, "quietTail": quiet, "stopPending": pendingStop,
                    "stopResultAcknowledged": stopResultAcknowledged,
                    "receivedPackets": receivedPackets, "receivedAudioBytes": receivedAudioBytes,
                    "droppedPackets": droppedPackets, "droppedAudioBytes": droppedAudioBytes,
                    "savedTailPackets": tailPackets, "dropReasons": dropReasons,
                    "stopRequestLimitSeconds": 25, "receiveLimitSeconds": 30,
                    "format": "uint32le length + original business envelope; NOT verified opus/wav", "events": events], options: [.prettyPrinted, .sortedKeys])
                try data.write(to: directory.appendingPathComponent("manifest.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        } catch { self.error = "파일 마무리에 실패했습니다. 수신 원본은 유지하지만 완전한 녹음으로 표시하지 않습니다." }
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}

struct AlwaysOnLocalProbeView: View {
    @ObservedObject var probe: AlwaysOnLocalProbe
    @State private var consent = false
    @State private var confirmPhysicalStop = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    Text("일상 기록 · 짧은 로컬 테스트").font(.headline)
                    Text("A1–A8 프로토콜 테스트이며 상시 녹음 기능이 아닙니다. 25초에 중지를 요청하고 30초에 수신을 끝냅니다. 위치, 일정, 클라우드 전사는 사용하지 않습니다.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text(probe.status).accessibilityIdentifier("always-on-status")
                    Text("현재 단계 남은 시간 \(probe.remaining)초\n수신 \(probe.receivedPackets) 패킷 / \(probe.receivedAudioBytes)바이트\n저장 \(probe.packetCount) 패킷 / \(probe.audioBytes)바이트 (종료 패킷 \(probe.tailPackets))\n폐기 \(probe.droppedPackets) 패킷 / \(probe.droppedAudioBytes)바이트")
                        .font(.caption).accessibilityIdentifier("always-on-counters")
                    if let error = probe.error { Text(error).foregroundStyle(Palette.amber) }
                    Toggle("이번 오디오를 이 기기에 저장하는 데 동의", isOn: $consent).disabled(probe.occupied).accessibilityIdentifier("always-on-consent")
                    Button("30초 로컬 테스트 시작") { probe.start(); consent = false }
                        .disabled(!consent || !probe.canStart).accessibilityIdentifier("always-on-start")
                    Button("중지 / 끄기 요청 재전송", role: .destructive) { probe.stop() }
                        .disabled(!probe.occupied).accessibilityIdentifier("always-on-stop")
                    if probe.canConfirmPhysicalStop {
                        Button("안경의 기록 기능이 꺼진 것을 확인함") { confirmPhysicalStop = true }
                            .accessibilityIdentifier("always-on-confirm-off")
                        Text("안경의 일상 기록 기능이 꺼진 것을 직접 확인한 뒤 누르세요. 설정 성공 응답만으로 꺼짐을 확인할 수 없으며 수동 확인은 별도로 기록합니다.")
                            .font(.caption).foregroundStyle(Palette.amber)
                    }
                    Text("시작 전에 주변 사람에게 알리고 테스트 문장을 사용하세요. AI 음성 대기를 일시정지하며 종료 후 클라우드 수집을 자동 재개하지 않습니다. 연결을 유지하고 안경 상태를 확인하세요.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                if let path = probe.directory { Text("로컬 원시 파일: \(path.lastPathComponent)\n형식 확인 전에는 재생 가능한 녹음으로 표시하지 않습니다. 안경의 기존 캐시를 조회하거나 삭제하지 않습니다.").font(.caption) }
                Card {
                    Text("프로토콜 이벤트 (오디오 내용 없음)").font(.headline)
                    ForEach(Array(probe.events.enumerated()), id: \.offset) { _, event in Text(event).font(.system(.caption, design: .monospaced)) }
                }
            }.padding(22)
        }.background(Palette.background).navigationTitle("일상 기록").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .confirmationDialog("안경에서 일상 기록 기능이 꺼진 것을 확인했나요? 수동 확인을 기록하며 프로토콜 검증 통과로 표시하지 않습니다.", isPresented: $confirmPhysicalStop) {
                Button("안경 기록 기능 꺼짐 확인") { probe.confirmPhysicalStop() }
                Button("취소", role: .cancel) {}
            }
    }
}
