import Foundation
import Combine
import RayNeoDisplay
import RayNeoProtocol
import UIKit

@MainActor final class CompanionDeviceFeatures: ObservableObject {
    @Published private(set) var status = "안경 연결 후 사용할 수 있습니다. 오디오 수집은 자동 시작하지 않습니다"
    @Published private(set) var recordingStatus = "안경 녹음 수신 꺼짐"
    @Published private(set) var recordingID: String?
    @Published private(set) var recordingBytes = 0
    @Published private(set) var acceptsEyeRecording = false
    @Published private(set) var todoStatus = "동기화 안 됨"
    @Published private(set) var battery: Int?
    @Published private(set) var brightness: Int?
    @Published private(set) var settings: [String: Any] = [:]
    @Published private(set) var completedRecording: URL?
    @Published private(set) var recoveryEntries: [GlassesRecordingInbox.Entry] = []
    @Published private(set) var recoveryBusy = false
    @Published private(set) var recoveryStatus = "이 기기의 파일만 검색하며 안경에 접근하지 않습니다."
    @Published var error: String?
    let voice: CompanionVoiceRuntime
    private weak var store: CompanionStore?
    private let inbox: GlassesRecordingInbox
    private let io = DispatchQueue(label: "companion.recording.inbox", qos: .utility)
    private let writeSlots = DispatchSemaphore(value:64)
    private var failedRecordings = Set<String>()
    private var captureDevice: String?
    private var recordTimeRaw: Int64?
    private var finishing = Set<String>()
    private var finalizationInFlight = false
    private var pendingSettings: [String: Date] = [:]
    private var observers: [NSObjectProtocol] = []
    var canControl: Bool { voice.ready && !recoveryBusy && store?.alwaysOn.occupied != true && !["recording", "processing", "displaying"].contains(voice.phase) }
    init(voice: CompanionVoiceRuntime, store: CompanionStore, root: URL) {
        self.voice = voice; self.store = store; inbox = GlassesRecordingInbox(root: root)
        voice.onBusiness = { [weak self] in self?.receive(device: $0, business: $1, data: $2) }
        voice.onBusinessLoss = { [weak self] in self?.lostMessages(); self?.store?.alwaysOn.lostMessages() }
        // One automatic weather owner. Legacy Weatherstack stays manual to avoid overwrites.
        voice.onRuntimeRefresh = { [weak self] in self?.store?.qweather.tick() }
        voice.featureIsBusy = { [weak self] in self?.recordingID != nil || self?.teleprompterID != nil || self?.store?.alwaysOn.occupied == true }
        voice.onConnectionChange = { [weak self] device in
            guard let self else { return }
            self.store?.notifications.connectionChanged()
            self.store?.headControlTest.connectionChanged()
            self.store?.alwaysOn.connectionChanged()
            self.pendingSettings.removeAll(); self.settings = [:]; self.battery = nil; self.brightness = nil
            if self.recordingID != nil { self.recordingStatus = device == self.captureDevice ? "다시 연결됨 · 같은 녹음의 상태와 데이터 대기 중. 이어받기 완료는 확인 전입니다" : "연결 중단 · 녹음 원본을 유지하며 같은 안경의 재연결을 기다립니다" }
            if self.teleprompterID != nil, device != self.teleprompterDevice {
                self.teleprompterPrepared = false
                self.teleprompterStatus = "프롬프터 연결 중단 · 자동 동작을 멈췄습니다. 다시 연결한 뒤 종료하고 원고를 다시 준비하세요"
            }
        }
        for (name, foreground) in [(UIApplication.didEnterBackgroundNotification,false),(UIApplication.didBecomeActiveNotification,true)] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.recordingID != nil, self.voice.deviceID == self.captureDevice else { return }
                    self.perform { try self.send(14,14,["isAppForeground":foreground]) }
                }
            })
        }
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    func prepare() { voice.prepare(); voice.refresh() }
    private func send(_ business: UInt8, _ type: UInt32, _ json: [String: Any]) throws {
        guard voice.deviceID != nil else { throw DeviceFeatureError.disconnected }
        try voice.sendBusiness(business, payload: DeviceBusinessWire.encode(type: type, json: json))
    }
    func perform(_ body: () throws -> Void) {
        do { try body(); error = nil } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "작업 실패 · 안경에서 완료됐는지 확인할 수 없습니다." }
    }
    func enableEyeRecording(_ enabled: Bool) {
        guard recordingID == nil else { error = "녹음을 중지한 뒤 파일 수신이 끝날 때까지 기다리세요."; return }
        acceptsEyeRecording = enabled
        recordingStatus = enabled ? "수신 허용됨 · 안경에서 녹음을 시작하세요. 이 기기에만 저장합니다" : "안경 녹음 수신 꺼짐"
    }
    func startRecording() {
        perform {
            guard canControl, recordingID == nil, teleprompterID == nil, let device = voice.deviceID else { throw DeviceFeatureError.busy }
            // Voice standby is explicitly suspended so an unsolicited wake cannot steal the microphone.
            if voice.enabled { voice.stop() }
            acceptsEyeRecording = true
            let id = UUID().uuidString
            captureDevice = device; recordingID = id; recordingBytes = 0; completedRecording = nil; recordTimeRaw = nil
            recordingStatus = "로컬 수신 폴더 준비 중"
            io.async { [weak self, inbox] in
                do {
                    try inbox.begin(device: device, id: id)
                    DispatchQueue.main.async {
                        guard let self, self.recordingID == id, self.voice.deviceID == device else { return }
                        self.perform {
                            try self.send(14,14,["isAppForeground": true])
                            try self.send(14,1,["uuid":id,"action":1,"code":1])
                            self.recordingStatus = "시작 요청됨 · 안경 응답 대기 중"
                        }
                    }
                } catch { DispatchQueue.main.async { self?.error = "수신 폴더를 만들지 못해 안경 녹음을 요청하지 않았습니다."; self?.recordingID = nil } }
            }
        }
    }
    func recordingControl(_ type: UInt32) {
        perform {
            guard let id = recordingID, voice.deviceID == captureDevice, [4,8,9,11].contains(type) else { throw DeviceFeatureError.noSession }
            var body: [String: Any] = ["uuid": id, "action": type == 11 ? 2 : 1, "code": type == 4 ? 2 : 1]
            // Preserve a reported raw time; never invent an epoch/elapsed-time conversion.
            if type == 9, let time = recordTimeRaw { body["time"] = time }
            try send(14,type,body)
            recordingStatus = type == 4 ? "중지 요청됨 · 남은 오디오와 완료 메시지 대기 중" : "제어 요청됨 · 안경 응답 대기 중"
        }
    }
    func receive(device: String, business: UInt8, data: Data) {
        guard voice.deviceID == device else { return }
        if business == 13 || business == 15 { store?.alwaysOn.receive(device: device, business: business, packet: data) }
        do {
            let wire = try DeviceBusinessWire(data)
            switch business {
            case 14: try recording(device,wire)
            case 22: try todo(device,wire)
            case 15:
                store?.qweather.receive(device:device,wire:wire)
                launcher(wire)
            case 20: try teleprompterReceive(device,wire)
            case 21:
                store?.notifications.receive(device: device, wire: wire)
                store?.headControlTest.receive(device: device, wire: wire)
            default: break
            }
        } catch {
            self.error = "인식할 수 없거나 일치하지 않는 데이터 수신 · 성공으로 처리하지 않았습니다."
            if business == 14 { lostMessages() }
        }
    }
    private func recording(_ device: String, _ wire: DeviceBusinessWire) throws {
        let j = wire.json, type = wire.type
        if type == 12 { recordingStatus = "동기화 목록 수신됨 · 이 버전은 오프라인 녹음을 자동으로 가져오거나 정리하지 않습니다"; return }
        guard let id = DeviceBusinessWire.identifier(j,"uuid") else { return }
        if type == 3, finishing.contains(id), recordingID != id, captureDevice == device {
            error = "녹음 파일 생성 후 추가 데이터가 도착했습니다. 사본을 보관하고 다시 확인하세요. 완전성을 보장할 수 없습니다."
            io.async { [inbox] in inbox.invalidate(device:device,id:id) }
            return
        }
        let action = DeviceBusinessWire.integer(j,"action"), code = DeviceBusinessWire.integer(j,"code")
        if type == 1, action == 1 {
            guard acceptsEyeRecording, teleprompterID == nil, recordingID == nil || (recordingID == id && captureDevice == device), canControl else { return }
            if voice.enabled { voice.stop() }
            recordingID = id; captureDevice = device; recordingBytes = 0; completedRecording = nil
            io.async { [weak self, inbox] in
                do {
                    try inbox.begin(device: device,id: id)
                    DispatchQueue.main.async {
                        guard let self, self.recordingID == id, self.voice.deviceID == device else { return }
                        self.perform { try self.send(14,1,["uuid":id,"action":2,"code":1]); self.recordingStatus = "안경 녹음 수신 준비됨 · 데이터 대기 중" }
                    }
                } catch { DispatchQueue.main.async { self?.error = "안경 녹음용 저장 공간을 준비할 수 없습니다." } }
            }
            return
        }
        guard recordingID == id, captureDevice == device else { return }
        if let time = DeviceBusinessWire.integer(j,"time") { recordTimeRaw = time }
        if type == 1, action == 2 {
            if code == 1 { recordingStatus = "안경에서 녹음 시작을 확인했습니다" }
            else { recordingStatus = "안경이 시작을 거부했습니다. code=\(code ?? -1). 권한이나 충돌 제한을 우회하지 않았습니다"; recordingID = nil }
        } else if type == 3 {
            guard let offset = DeviceBusinessWire.integer(j,"offset"), offset >= 0,
                  offset <= GlassesRecordingInbox.limit, !wire.bytes.isEmpty else { throw DeviceFeatureError.invalidPacket }
            guard writeSlots.wait(timeout:.now()) == .success else { lostMessages(); return }
            io.async { [weak self, inbox, writeSlots] in
                defer { writeSlots.signal() }
                do { let count = try inbox.append(device:device,id:id,offset:Int(offset),data:wire.bytes)
                    DispatchQueue.main.async { self?.recordingBytes = count; self?.recordingStatus = "원본 오디오 수신 및 저장 중" }
                } catch { inbox.invalidate(device:device,id:id); DispatchQueue.main.async { self?.error = "오디오 저장 또는 완전성 검사 실패 · 원본을 유지하며 완전한 녹음으로 표시하지 않습니다." } }
            }
        } else if type == 6, DeviceBusinessWire.boolean(j,"completed") == true, !finishing.contains(id) {
            // Persist the observed completion before queued finalization, so a restart cannot invent or lose it.
            io.async { [inbox] in
                do { try inbox.recordCompletion(device:device,id:id) }
                catch { inbox.invalidate(device:device,id:id) }
            }
            finishing.insert(id); recordingStatus = "안경에서 완료 보고됨 · 수신 범위 확인 후 파일 생성 중"
            // Small grace for callbacks delivered after completion. Late data is never silently merged into a published file.
            DispatchQueue.main.asyncAfter(deadline: .now()+1) { [weak self] in self?.finishRecording(device:device,id:id) }
        } else if type == 4 {
            if action == 1 { try send(14,4,["uuid":id,"action":2,"code":code ?? 1]) }
            recordingStatus = "중지 이벤트 수신됨 · 오디오 완료 대기 중"
        } else if type == 11 {
            if action == 1 { try send(14,11,["uuid":id,"action":2,"code":1]) }
            let time = DeviceBusinessWire.integer(j,"time") ?? 0
            io.async { [inbox] in try? inbox.mark(device:device,id:id,time:time) }
        } else if type == 8 || type == 9 {
            if action == 1 { try send(14,type,["uuid":id,"action":2,"code":1]) }
            recordingStatus = code == 1 ? (type == 8 ? "안경에서 일시정지됨" : "안경에서 재개됨") : "제어 응답 code=\(code ?? -1)"
        } else if type == 5 { recordingStatus = "같은 녹음의 재연결 상태 수신됨 · offset 검증 계속" }
    }
    private func finishRecording(device: String, id: String) {
        guard !finalizationInFlight else { return }
        finalizationInFlight = true
        io.async { [weak self, inbox] in
            do {
                _ = try inbox.finish(device:device,id:id)
                let output = try inbox.decodedDerivative(device:device,id:id)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.finalizationInFlight = false
                    self.completedRecording = output; self.recordingID = nil
                    self.recordingStatus = "수신 범위와 패킷 디코딩 검증 통과 · WAV 보관 대기 중. 원본과 Ogg는 유지하며 무선 오디오 무손실을 보장하지 않습니다."
                    // Archive copy + checksum, not ASR or upload. Ogg structure is not proof of acoustic completeness.
                    Task { await self.archiveReceivedRecording() }
                }
            } catch {
                DispatchQueue.main.async { self?.finalizationInFlight = false; self?.recordingStatus = "파일 생성을 완료하지 못했습니다. 원시 데이터와 수신 범위 기록은 유지합니다"; self?.error = "녹음 완전성 검사 실패 · 완전한 오디오로 표시하지 않습니다." }
            }
        }
    }
    private func lostMessages() {
        store?.notifications.lostMessages()
        if let id = recordingID, let device = captureDevice, failedRecordings.insert(id).inserted { io.async { [inbox] in inbox.invalidate(device:device,id:id) } }
        error = "수신 큐 초과 또는 녹음 형식 불일치 · 이번 녹음의 완전성은 확인되지 않았습니다."
    }
    func archiveReceivedRecording() async {
        guard let file = completedRecording, let store else { return }
        let imported = await store.archive.importFile(file,title:"안경 녹음 " + Date().formatted(date:.abbreviated,time:.shortened))
        recordingStatus = imported ? "WAV 검증 및 보관 완료 · 원본/Ogg 유지. 전사나 업로드는 하지 않았습니다" : "WAV 저장됨 · 보관 실패. 보관 재시도 또는 파일 공유 가능"
    }
    func retryRecordingFinish() {
        guard let id = recordingID, let device = captureDevice, finishing.contains(id) else { error = "안경의 완료 메시지를 받지 못했습니다. 완료로 처리할 수 없습니다."; return }
        finishRecording(device:device,id:id)
    }
    func loadRecoveryEntries() async {
        guard !recoveryBusy, recordingID == nil, !finalizationInFlight else { recoveryStatus = "수신 작업이 있습니다. 종료 후 다시 검색하세요."; return }
        recoveryBusy = true; defer { recoveryBusy = false }
        do {
            let catalog: GlassesRecordingInbox.Catalog = try await withCheckedThrowingContinuation { continuation in
                io.async { [inbox] in continuation.resume(with:Result { try inbox.catalog() }) }
            }
            recoveryEntries = catalog.entries
            recoveryStatus = "이 기기 \(catalog.entries.count)개 · \(catalog.unreadable)개 폴더를 읽지 못해 그대로 유지합니다. 검색은 완전성 검증이 아닙니다."
        } catch { recoveryStatus = "수신 폴더를 읽을 수 없습니다. 초기화, 재생성 또는 삭제하지 않았습니다." }
    }
    func recoverRecording(_ entryID: String) async {
        guard !recoveryBusy, recordingID == nil, !finalizationInFlight else { return }
        recoveryBusy = true; defer { recoveryBusy = false }
        do {
            let file: URL = try await withCheckedThrowingContinuation { continuation in
                io.async { [inbox] in continuation.resume(with:Result { try inbox.recoverDecoded(entryID) }) }
            }
            guard let store else { return }
            let imported = await store.archive.importFile(file,title:"복구한 안경 녹음")
            recoveryStatus = imported ? "재검증, 디코딩 및 보관 완료 · 전사, 업로드, 원본 삭제 없음" : "WAV 복구됨 · 보관 실패. 원본을 유지하며 재시도할 수 있습니다."
        } catch { recoveryStatus = "복구 검증 실패 또는 디코딩 미지원 · 원본을 유지하며 완전한 녹음으로 표시하지 않습니다." }
    }
    func recoveryRawFile(_ entryID: String) async -> URL? {
        guard !recoveryBusy, recordingID == nil, !finalizationInFlight else { return nil }
        recoveryBusy = true; defer { recoveryBusy = false }
        do {
            let url: URL = try await withCheckedThrowingContinuation { continuation in
                io.async { [inbox] in continuation.resume(with:Result { try inbox.exportRawCopy(entryID) }) }
            }
            return url
        } catch { recoveryStatus = "원본 파일을 읽을 수 없어 공유를 준비하지 못했습니다."; return nil }
    }
    func syncTodos(pendingOnly: Bool = false) {
        perform {
            guard canControl, let device = voice.deviceID, let store else { throw DeviceFeatureError.disconnected }
            let rows = try store.todoCandidates(device: device, pendingOnly: pendingOnly)
            guard rows.count <= 100 else { throw DeviceFeatureError.storageLimit }
            for row in rows { try sendTodo(row, device:device) }
            todoStatus = "전송됨 \(rows.count)개 할 일 · 안경 응답 대기 중. 표시 완료는 별도 확인하세요"
        }
    }
    func localTodoChanged(_ row: LocalTodo) {
        guard canControl, row.archivedAt == nil, row.wireDeviceID == voice.deviceID,
              row.wireID != nil, row.delivery?.conflict == nil else { return }
        perform { guard let device = voice.deviceID else { throw DeviceFeatureError.disconnected }; try sendTodo(row,device:device) }
    }
    private func sendTodo(_ row: LocalTodo, device: String) throws {
        guard let store else { throw DeviceFeatureError.noSession }
        let current = try store.prepareTodoSubmission(row.id, device: device)
        guard let id = current.wireID, let revision = current.delivery?.revision else { throw TodoDeliveryError.missing }
        let seconds = Int64(Date().timeIntervalSince1970)
        let body: [String:Any] = ["eventType":1,"eventID":id,"createTime":Int64(current.createdAt.timeIntervalSince1970),
            "title":current.title,"isImportant":current.important ?? false,"status":current.completed ? 1 : 0,"lastModifiedTime":seconds]
        try send(22,2,body)
        store.markTodoSubmitted(row.id, device: device, revision: revision)
    }
    private func todo(_ device: String, _ wire: DeviceBusinessWire) throws {
        if wire.type == 14 { todoStatus = "안경 작업 응답: 성공 \(DeviceBusinessWire.integer(wire.json,"successCount") ?? 0) · 항목별 표시 확인과는 별개입니다"; return }
        guard wire.type == 4 || wire.type == 10 else { return }
        let data = try JSONSerialization.data(withJSONObject:wire.json)
        let message = try TodoJSONCodec().decodeGlassesMessage(type:UInt16(wire.type),payload:data)
        var changes = 0
        switch message {
        case .status(let s): changes += store?.applyGlassesTodo(device:device,id:s.eventID,status:s.statusRaw,important:s.isImportant.value) == true ? 1 : 0
        case .batch(let b):
            for entry in b.eventList.value ?? [] { if case .todo(let s) = entry { changes += store?.applyGlassesTodo(device:device,id:s.eventID,status:s.statusRaw,important:s.isImportant.value) == true ? 1 : 0 } }
        default: break
        }
        todoStatus = "안경 상태 반영됨 \(changes)개 · 오프라인 충돌은 전송 대기 목록에서 처리하며 알 수 없는 ID는 가져오지 않습니다"
    }
    func refreshSettings() {
        perform {
            try voice.sendBusiness(15,payload:LauncherControlPrototype.encode(.requestGeneralStatus))
            try send(15,4,["cmd":"request_general_settings","payload":["value":0,"mode":0,"data":""]])
            status = "조회 요청됨 · 안경 상태 대기 중"
        }
    }
    func setBrightness(_ value: Int) { command(type:2,cmd:"brightness_change",value:value,allowed:7...8) }
    func setHeadControl(_ enabled: Bool, mode: Int) {
        guard [0,1].contains(mode) else { return }; command(type:5,cmd:"head_gestures",value:enabled ? 1:0,mode:mode)
    }
    func setSleep(_ seconds: Int) { guard [15,25].contains(seconds) else { return }; command(type:5,cmd:"auto_lock_time",value:seconds) }
    func setDoubleTapTodo(_ todo: Bool) {
        guard let crown = settings["crownConfig"] as? [String:Any] ?? settings["crown_config"] as? [String:Any],
              let long = DeviceBusinessWire.integer(crown,"longPress") else { error = "기존 길게 누르기 설정을 덮어쓰지 않도록 전체 다이얼 설정을 먼저 읽으세요."; return }
        perform { let body = try JSONSerialization.data(withJSONObject:["double":todo ? 8:0,"longPress":long]); try submitCommand(type:5,cmd:"crown_config",value:0,mode:0,data:String(decoding:body,as:UTF8.self)) }
    }
    func setDisplay(height: Int? = nil, distance: Int? = nil) {
        guard let config = settings["displayConfig"] as? [String:Any] ?? settings["display_config"] as? [String:Any],
              let oldHeight = DeviceBusinessWire.integer(config,"height"), let oldDistance = DeviceBusinessWire.integer(config,"distance"),
              height == nil || [1,3,5].contains(height!), distance == nil || [1,2].contains(distance!) else {
            error = "표시 설정을 먼저 읽으세요. 확인된 단계만 지원하며 다른 매개변수는 덮어쓰지 않습니다."; return
        }
        perform {
            let data = try JSONSerialization.data(withJSONObject:["height":height.map(Int64.init) ?? oldHeight,"distance":distance.map(Int64.init) ?? oldDistance])
            try submitCommand(type:5,cmd:"display_config",value:0,mode:0,data:String(decoding:data,as:UTF8.self))
        }
    }
    func sendWeatherstack(_ snapshot: WeatherstackSnapshot, icon: Int) {
        perform { try submitWeatherstack(snapshot, icon: icon) }
    }
    func submitWeatherstack(_ snapshot: WeatherstackSnapshot, icon: Int) throws {
        guard snapshot.canSend(at:Date()) else { throw WeatherstackError.stale }
        guard (0...999).contains(icon) else { throw WeatherstackError.icon }
        try submitWeather(location:snapshot.city,temperature:snapshot.lensTemperature,icon:icon,description:snapshot.description)
    }
    func sendWeather(location: String, temperature: Int, icon: Int, description: String, current: Bool = true) {
        perform { try submitWeather(location:location,temperature:temperature,icon:icon,description:description,current:current) }
    }
    private func submitWeather(location: String, temperature: Int, icon: Int, description: String, current: Bool = true) throws {
            guard canControl, !location.isEmpty, location.utf8.count <= 80, (-80...60).contains(temperature), (0...999).contains(icon) else { throw DeviceFeatureError.invalidPacket }
            let update = SelectedCityWeatherRawUpdate(items:[CityWeatherRawItem(location:location,locationID:"companion-custom",temperatureRaw:Int64(temperature),iconRaw:Int64(icon),descriptionRaw:description,temperatureRangeRaw:"",hourly:[])],timestampRaw:String(Int64(Date().timeIntervalSince1970)))
            let msg = try current ? WeatherJSONCodec().encodeCurrentWeatherUpdate(CurrentWeatherRawUpdate(location:location,temperatureRaw:Int64(temperature),iconRaw:Int64(icon),timestampRaw:update.timestampRaw)) : CityWeatherJSONCodec().encodeUpdate(update)
            try voice.sendBusiness(15,payload:DeviceBusinessWire.encode(type:UInt32(msg.type),json:JSONSerialization.jsonObject(with:msg.payload) as! [String:Any]))
            pendingSettings[current ? "current_weather_update" : "weather_update"] = Date(); status = "사용자 날씨 데이터 전송됨 · 레이아웃은 유지하며 응답 대기 중"
    }
    private func command(type: UInt32, cmd: String, value: Int, mode: Int = 0, allowed: ClosedRange<Int>? = nil) {
        perform { if let allowed, !allowed.contains(value) { throw DeviceFeatureError.invalidPacket }; try submitCommand(type:type,cmd:cmd,value:value,mode:mode,data:"") }
    }
    private func submitCommand(type: UInt32, cmd: String, value: Int, mode: Int, data: String) throws {
        guard canControl else { throw DeviceFeatureError.busy }
        if let since = pendingSettings[cmd], Date().timeIntervalSince(since) < 8 { throw DeviceFeatureError.busy }
        try send(15,type,["cmd":cmd,"payload":["value":value,"mode":mode,"data":data]])
        pendingSettings[cmd] = Date(); status = "설정 요청됨 · 안경 응답 전에는 표시값을 바꾸지 않습니다"
    }
    private func launcher(_ wire: DeviceBusinessWire) {
        let j = wire.json
        if wire.type == 1 {
            let state = j["generalStatus"] as? [String:Any] ?? j
            if let n = DeviceBusinessWire.integer(state,"battery") { battery = Int(n) }
            if let n = DeviceBusinessWire.integer(state,"brightness") { brightness = Int(n) }
        }
        if wire.type == 4 { settings = j["generalSettings"] as? [String:Any] ?? j; status = "안경 일반 설정을 받았습니다" }
        guard let cmd = j["cmd"] as? String, let p = j["payload"] as? [String:Any] else { return }
        if wire.type == 3, cmd == "brightness_change", let n = DeviceBusinessWire.integer(p,"value") { brightness = Int(n) }
        if [3,6,17,19].contains(wire.type) {
            if wire.type == 6, let body = p["data"] as? String, let bytes = body.data(using:.utf8),
               let config = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
               let key = ["display_config":"displayConfig","crown_config":"crownConfig","privacy_config":"privacyConfig"][cmd] {
                settings[key] = config
            }
            pendingSettings.removeValue(forKey:cmd)
            status = "안경 응답 \(cmd.prefix(45))：\(DeviceBusinessWire.integer(p,"value") ?? -1) (실제 안경 표시 미확인)"
        }
    }

    // Teleprompter state/transport is implemented in the dedicated extension below.
    @Published private(set) var teleprompterStatus = "원고 전송 전"
    @Published private(set) var teleprompterID: String?
    @Published private(set) var teleprompterOffset: Int64 = 0
    var teleprompterFile: URL?
    var teleprompterDevice: String?
    var teleprompterPrepared = false
    var teleprompterSentFile = false
    var teleprompterTransferTask: String?
}

extension CompanionDeviceFeatures {
    func prepareTeleprompter(_ text: String, speed: Int) {
        perform {
            guard canControl, recordingID == nil, teleprompterID == nil, let device = voice.deviceID else { throw DeviceFeatureError.busy }
            guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.count <= 12_000,
                  text.utf8.count <= 48_000, (60...240).contains(speed) else { throw DeviceFeatureError.invalidPacket }
            if voice.enabled { voice.stop() }
            let did = UUID().uuidString
            let dir = inbox.root.deletingLastPathComponent().appendingPathComponent("TeleprompterOutboxV1")
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            guard try FileManager.default.contentsOfDirectory(atPath:dir.path).count < 100 else { throw DeviceFeatureError.storageLimit }
            let url = dir.appendingPathComponent(did + ".txt")
            try Data(text.utf8).write(to:url,options:[.withoutOverwriting,.completeFileProtectionUntilFirstUserAuthentication])
            teleprompterID = did; teleprompterDevice = device; teleprompterFile = url
            teleprompterOffset = 0; teleprompterPrepared = false; teleprompterSentFile = false
            // Optional layout fields intentionally omitted: never guess pixel/gear defaults.
            try send(20,2,["action":1,"did":did,"total":text.utf8.count,"scroll":2,"speed":speed,"pageOffset":0,"highLightOffset":0])
            teleprompterStatus = "원고 준비 요청됨 · 안경 응답 대기 중. 음성 추적/마이크는 사용하지 않습니다"
            DispatchQueue.main.asyncAfter(deadline:.now()+30) { [weak self] in
                guard let self, self.teleprompterID == did, !self.teleprompterPrepared else { return }
                self.teleprompterStatus = "준비 시간 초과 · 원고 수신 미확인으로 자동 스크롤을 시작하지 않습니다. 나가기를 눌러 취소할 수 있습니다."
            }
        }
    }
    func teleprompterControl(_ type: UInt32, speed: Int = 120) {
        perform {
            guard let did = teleprompterID, teleprompterDevice == voice.deviceID,
                  type == 6 || teleprompterPrepared else { throw DeviceFeatureError.noSession }
            guard [3,4,5,6,7].contains(type) else { throw DeviceFeatureError.invalidPacket }
            var body: [String:Any] = ["action":1,"did":did]
            if type == 4 { body["offset"] = teleprompterOffset; body["code"] = 1; body["isCompleted"] = false }
            if type == 7 { guard (60...240).contains(speed) else { throw DeviceFeatureError.invalidPacket }; body["scroll"] = 2; body["speed"] = speed }
            try send(20,type,body)
            if type == 6, let task = teleprompterTransferTask { voice.cancelFile(task); teleprompterTransferTask = nil }
            teleprompterStatus = "제어 type\(type) 전송됨 · 안경 응답 대기 중"
        }
    }
    private func teleprompterReceive(_ device: String, _ wire: DeviceBusinessWire) throws {
        guard let did = DeviceBusinessWire.identifier(wire.json,"did"), did == teleprompterID, teleprompterDevice == device else { return }
        let action = DeviceBusinessWire.integer(wire.json,"action"), code = DeviceBusinessWire.integer(wire.json,"code")
        if wire.type == 2, action == 2 {
            guard code == 1 || code == 7 else { teleprompterStatus = "준비 거부됨 code=\(code ?? -1) · 충돌을 자동으로 처리하지 않았습니다"; return }
            if !teleprompterSentFile {
                guard let file = teleprompterFile else { throw DeviceFeatureError.noSession }
                teleprompterTransferTask = try voice.sendFile(file,id:did)
                teleprompterSentFile = true
                teleprompterStatus = "파일 전송됨 · 원고 수신 확인 대기 중. 아직 재생하지 않았습니다"
            } else { teleprompterPrepared = true; teleprompterStatus = "파일 전송 후 성공 응답을 받았습니다. 시작을 테스트할 수 있으며 실제 안경 표시는 별도 확인해야 합니다" }
            return
        }
        if wire.type == 3, action == 2 { teleprompterStatus = "프롬프터 시작 응답 code=\(code ?? -1)"; return }
        guard let control = TeleprompterControlType(rawValue: UInt16(clamping:wire.type)) else { return }
        let data = try JSONSerialization.data(withJSONObject:wire.json)
        if action == 1 {
            let event = try TeleprompterJSONCodec().decodeGlassesRequest(type:control.rawValue,payload:data)
            switch event {
            case .progress(let p): teleprompterOffset = p.pageOffset; teleprompterStatus = "안경 진행률: UTF-8 원본 offset \(p.pageOffset)"
            case .pause: teleprompterStatus = "안경에서 일시정지 요청"
            case .resume: teleprompterStatus = "안경에서 재개 요청"
            case .stop: teleprompterStatus = "안경에서 종료 요청"
            default: return
            }
            let ack = try TeleprompterJSONCodec().encodeAppResponse(type:control,did:did,code:.accepted)
            try voice.sendBusiness(20,payload:DeviceBusinessWire.encode(type:UInt32(ack.type),json:JSONSerialization.jsonObject(with:ack.payload) as! [String:Any]))
        } else if action == 2 { teleprompterStatus = "안경 응답 type\(wire.type) code=\(code ?? -1)" }
        if control == .stop, action == 1 || code == 1 {
            if let task = teleprompterTransferTask { voice.cancelFile(task); teleprompterTransferTask = nil }
            teleprompterID = nil; teleprompterPrepared = false; teleprompterFile = nil
        }
    }
}
