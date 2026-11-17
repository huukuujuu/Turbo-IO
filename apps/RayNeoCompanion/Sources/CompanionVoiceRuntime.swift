import SwiftUI
import Combine

@MainActor final class CompanionVoiceRuntime: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var enabled = false
    @Published private(set) var phase = "disabled"
    @Published private(set) var transcript = ""
    @Published private(set) var answer = ""
    @Published private(set) var transcriptFinal = false
    @Published private(set) var modelComplete = false
    @Published private(set) var hasCredentials = false
    @Published private(set) var continuous = false
    @Published private(set) var cloud = false
    @Published private(set) var latestEvent = "기기 통신 모듈 로딩 전"
    @Published var error: String?
    @Published private(set) var testingModel = false
    @Published private(set) var modelTestResult = ""
    private let timeline: ConversationTimeline?
    weak var codex: CodexCompanion?
    private var activeTurn: UUID?
    var onBusiness: ((String, UInt8, Data) -> Void)?
    var onBusinessLoss: (() -> Void)?
    var featureIsBusy: (() -> Bool)?
    var onConnectionChange: ((String?) -> Void)?
    var onRuntimeRefresh: (() -> Void)?
    private var previousDeviceID: String?
    var deviceID: String? {
        #if COMPANION_DEVICE
        return controller.companionDeviceID
        #else
        return nil
        #endif
    }
    func sendBusiness(_ index: UInt8, payload: Data) throws {
        #if COMPANION_DEVICE
        prepare(); try controller.companionSendBusiness(index, payload: payload)
        #else
        throw DeviceFeatureError.disconnected
        #endif
    }
    func sendFile(_ url: URL, id: String) throws -> String {
        #if COMPANION_DEVICE
        return try controller.companionSendFile(url,id:id)
        #else
        throw DeviceFeatureError.disconnected
        #endif
    }
    func cancelFile(_ task: String) {
        #if COMPANION_DEVICE
        controller.companionCancelFile(task)
        #endif
    }
    init(timeline: ConversationTimeline? = nil) { self.timeline = timeline }
    deinit {
        #if COMPANION_DEVICE
        poll?.invalidate()
        #endif
    }
    #if COMPANION_DEVICE
    let controller = ProbeController()
    private var poll: Timer?
    private var modelDiagnostic: CloudVoicePipeline?
    #endif
    var supportsDevice: Bool {
        #if COMPANION_DEVICE
        return true
        #else
        return false
        #endif
    }
    var phaseLabel: String {
        ["disabled": "음성 대기 꺼짐", "waitingForConnection": "연결 인증 대기 중", "idle": "안경에서 음성 호출 대기 중",
         "recording": "듣는 중", "processing": "응답 생성 중", "displaying": "응답 전송 완료 · 계속 말씀하세요"] [phase] ?? "상태 대기 중"
    }
    func prepare() {
        #if COMPANION_DEVICE
        guard poll == nil else { refresh(); return }
        controller.companionBusiness = { [weak self] in self?.onBusiness?($0,$1,$2) }
        controller.companionTools = { [weak self] in self?.codex?.toolDefinitions ?? [] }
        controller.companionExecuteTool = { [weak self] name, arguments, id in
            guard let codex = self?.codex else { return "Codex 도구가 설정되지 않아 실행하지 않았습니다." }
            return await codex.executeTool(name: name, arguments: arguments, requestID: id)
        }
        controller.companionBusinessLoss = { [weak self] in self?.onBusinessLoss?() }
        controller.companionLog = { [weak self] line in
            self?.latestEvent = String(line.prefix(200))
            if line.hasPrefix("클라우드 처리 오류: ") { self?.error = line }
        }
        controller.companionTranscript = { [weak self] id, text, final in
            guard let self, !text.isEmpty else { return }
            if self.activeTurn != id { self.finishTimelineTurn(); self.activeTurn = id }
            self.timeline?.record(ConversationEvent(id: id, kind: .transcript, text: text, final: final))
        }
        controller.companionCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .startAudio, .vadStart:
                DisplayObservation.shared.newUtterance()
                self.finishTimelineTurn()
                self.clearText()
            case .streamText(let text, let final): self.transcript = text; self.transcriptFinal = final
            case .text(let text): self.answer = text
            case .answer(let text, _, let id, _):
                self.answer = String((self.answer + text).prefix(8192))
                self.timeline?.record(ConversationEvent(id: id, kind: .answerDelta, text: text))
            case .responseComplete:
                self.modelComplete = true
                if let id = self.activeTurn { self.timeline?.record(ConversationEvent(id: id, kind: .completed)) }
            default: break
            }
        }
        controller.loadViewIfNeeded()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        poll = timer; RunLoop.main.add(timer, forMode: .common); refresh()
        #endif
    }
    func refresh() {
        #if COMPANION_DEVICE
        ready = controller.companionReady; enabled = controller.companionEnabled
        phase = controller.companionPhase; hasCredentials = CloudVoiceKeys.ready
        DisplayObservation.shared.connection(ready, phase:phase)
        if ["disabled", "waitingForConnection", "idle"].contains(phase) { finishTimelineTurn() }
        continuous = controller.companionContinuous; cloud = controller.companionCloud
        let current = deviceID
        if previousDeviceID != current { previousDeviceID = current; onConnectionChange?(current) }
        onRuntimeRefresh?()
        #endif
    }
    func discover() {
        #if COMPANION_DEVICE
        prepare(); controller.companionDiscover(); refresh()
        #endif
    }
    func connect() {
        #if COMPANION_DEVICE
        prepare(); controller.companionConnect(); refresh()
        #endif
    }
    func reconnectBonded() {
        #if COMPANION_DEVICE
        prepare(); controller.companionReconnectBonded(); refresh()
        #endif
    }
    func start(cloud: Bool, continuous: Bool) {
        guard featureIsBusy?() != true else { error = "안경 녹음이나 프롬프터를 종료한 뒤 음성 대기를 켜세요."; return }
        #if COMPANION_DEVICE
        prepare()
        guard controller.companionStart(cloud: cloud, continuous: continuous) else {
            error = "인증된 안경 한 대가 필요합니다. 클라우드 대화에는 ASR 및 모델 API 키도 필요합니다."; refresh(); return
        }
        refresh()
        #endif
    }
    func stop() {
        #if COMPANION_DEVICE
        controller.companionStop(); refresh()
        #endif
    }
    func endRound() {
        #if COMPANION_DEVICE
        controller.companionEndRound(); refresh()
        #endif
    }
    func saveKeys(asr: String, llm: String, host: String, enableDefault: Bool = false) -> Bool {
        #if COMPANION_DEVICE
        guard !enabled else { error = "음성 대기를 끈 뒤 클라우드 설정을 변경하세요."; return false }
        guard let target = CloudASRHostSettings.normalize(host) else { error = "Alibaba Cloud ASR 호스트명(aliyuncs.com)을 입력하세요. 프로토콜, 경로, 포트는 제외합니다."; return false }
        let service = CloudASRHostSettings.service(for: target)
        let a = asr.isEmpty ? CloudVoiceKeys.get(service) != nil : CloudVoiceKeys.save(asr, service: service)
        let b = llm.isEmpty ? CloudVoiceKeys.get(CloudVoiceKeys.llmService) != nil : CloudVoiceKeys.save(llm, service: CloudVoiceKeys.llmService)
        if a && b {
            CloudASRHostSettings.save(target)
            if enableDefault { controller.companionEnableDefaultCloudVoice() }
        }
        refresh()
        if !a || !b { error = "API 키를 모두 저장하지 못했습니다. 클라우드 업로드는 켜지지 않았습니다." }
        return a && b
        #else
        error = "시뮬레이터에는 실제 음성 서비스 키를 저장하지 않습니다."; return false
        #endif
    }
    func clearText() { transcript = ""; answer = ""; transcriptFinal = false; modelComplete = false }
    func testModelConnection() {
        #if COMPANION_DEVICE
        guard !testingModel else { return }
        error = nil
        modelTestResult = "DeepSeek 연결 테스트 중…"
        modelDiagnostic?.cancel(clearHistory: true)
        let pipeline = CloudVoicePipeline()
        modelDiagnostic = pipeline
        testingModel = true
        pipeline.log = { [weak self] line in
            NSLog("[CloudModelDiagnostic] %@", line)
            self?.latestEvent = KoreanDiagnostics.display(line)
            if line.hasPrefix("DeepSeek API 잔액 조회 ·") || line.hasPrefix("클라우드 처리 오류: ") {
                self?.modelTestResult += "\n" + line
            }
            if line.hasPrefix("클라우드 처리 오류: ") { self?.error = line }
        }
        pipeline.onError = { [weak self] _ in self?.testingModel = false }
        pipeline.onText = { [weak self] _, _, final in
            guard final else { return }
            self?.testingModel = false
            self?.latestEvent = "DeepSeek 연결 테스트 성공 · 텍스트 응답 수신 완료"
            self?.modelTestResult += "\nDeepSeek 연결 테스트 성공 · 텍스트 응답 수신 완료"
            NSLog("[CloudModelDiagnostic] DeepSeek connection test succeeded")
        }
        pipeline.testModelConnection()
        #endif
    }
    private func finishTimelineTurn() {
        if let id = activeTurn { timeline?.record(ConversationEvent(id: id, kind: .interrupted)); activeTurn = nil }
    }
}

#if COMPANION_DEVICE
struct VoiceDiagnosticsView: UIViewControllerRepresentable {
    let runtime: CompanionVoiceRuntime
    func makeUIViewController(context: Context) -> ProbeController { runtime.prepare(); return runtime.controller }
    func updateUIViewController(_ controller: ProbeController, context: Context) {}
}
#endif
