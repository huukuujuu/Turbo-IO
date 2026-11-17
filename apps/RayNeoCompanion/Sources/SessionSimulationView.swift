import SwiftUI
import RayNeoSession

@MainActor
final class SessionLabModel: ObservableObject {
    @Published private var machine = VoiceSessionMachine(configuration: .init(asrPolicy: .preferCloudWithLocalFallback, ttsMode: .enabled))
    @Published private(set) var events: [String] = []
    @Published private(set) var staleCallbackResult: String?
    private var previousRound: RoundToken?
    var snapshot: SessionSnapshot { machine.snapshot }

    func send(_ event: VoiceSessionEvent, label: String) {
        let effects = machine.handle(event)
        events.insert("\(label) → \(effects.count)개 이벤트", at: 0)
        for effect in effects.reversed() {
            events.insert("  \(effectName(effect))", at: 1)
        }
        events = Array(events.prefix(60))
    }

    func connect() { send(.connected, label: "연결 시뮬레이션") }
    func wake() { send(.wake, label: "호출 시뮬레이션") }
    func network(_ available: Bool) { send(.networkChanged(isAvailable: available), label: available ? "온라인 시뮬레이션" : "오프라인 시뮬레이션") }
    func transcript() {
        guard let round = snapshot.currentRound, let source = snapshot.asrSource else { return }
        send(.audioEnded(round: round), label: "음성 입력 종료 시뮬레이션")
        send(.asrResult(round: round, source: source, result: .init(revision: 1, text: "3 더하기 4는 얼마인가요?", isFinal: true)), label: "음성 인식 예시 입력")
    }
    func answer() {
        guard let round = snapshot.currentRound else { return }
        send(.modelText(round: round, update: .init(revision: 1, text: "3 더하기 4는 7입니다.")), label: "모델 응답 예시 입력")
        send(.modelFinished(round: round), label: "모델 응답 완료 시뮬레이션")
        send(.ttsStarted(round: round), label: "TTS 시작 시뮬레이션")
    }
    func finishSpeech() {
        guard let round = snapshot.currentRound else { return }
        send(.ttsInputFinished(round: round), label: "TTS 입력 완료 시뮬레이션")
        send(.ttsPlaybackDrained(round: round), label: "재생 버퍼 소진 시뮬레이션")
    }
    func nextRound() {
        guard let round = snapshot.currentRound else { return }
        previousRound = round
        send(.nextRound(round: round), label: "안경의 다음 대화 시뮬레이션")
    }
    func interrupt() {
        guard let round = snapshot.currentRound else { return }
        previousRound = round
        send(.interrupt(round: round), label: "중단 후 다음 대화 시작 시뮬레이션")
    }
    func staleCallback() {
        guard let round = previousRound else { return }
        let before = snapshot
        let effects = machine.handle(.modelText(round: round, update: .init(revision: 99, text: "만료된 예시 응답")))
        staleCallbackResult = effects.isEmpty && before == snapshot ? "이전 대화의 응답을 무시했습니다. 현재 대화는 유지됩니다" : "이전 대화의 응답이 상태를 변경했습니다. 코어를 확인하세요"
        events.insert(staleCallbackResult ?? "", at: 0)
    }
    func exit() { send(.exitRequested(reason: .normal), label: "종료 시뮬레이션") }
    var canTestStale: Bool { previousRound != nil }

    private func effectName(_ effect: VoiceSessionEffect) -> String {
        switch effect {
        case .startRecognition: return "인식 시작 (실행 안 함)"
        case .feedRecognition: return "오디오 제공 (실행 안 함)"
        case .finishRecognition: return "인식 입력 종료 (실행 안 함)"
        case .cancelRecognition: return "인식 취소 (실행 안 함)"
        case .startCapture: return "오디오 수집 시작 (실행 안 함)"
        case .stopCapture: return "오디오 수집 중지 (실행 안 함)"
        case .requestModel: return "모델 요청 (실행 안 함)"
        case .synthesizeAndPlay: return "음성 합성 및 재생 (실행 안 함)"
        case .cancelWork: return "현재 대화 작업 취소 (실행 안 함)"
        case .invalidateToolApprovals: return "현재 대화의 도구 권한 만료 (실행 안 함)"
        case .displayTranscript: return "인식 텍스트 표시 (전송 안 함)"
        case .displayResponse: return "응답 표시 (전송 안 함)"
        case .reportTTSStatus: return "TTS 상태 동기화 (전송 안 함)"
        case .responseComplete: return "응답 완료 이벤트 (전송 안 함 · 종료 아님)"
        case .requestExit: return "화면 종료 이벤트 (전송 안 함)"
        case .scheduleTimeout: return "시간 초과 예약 (실험에서는 타이머 실행 안 함)"
        case .cancelTimeout: return "시간 초과 취소 (실험에서는 타이머 실행 안 함)"
        case .reportFailure: return "오류 보고 (로컬 이벤트만)"
        }
    }
}

struct SessionSimulationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var lab = SessionLabModel()
    private var phaseName: String {
        switch lab.snapshot.phase {
        case .disconnected: return "시작 전"
        case .idle: return "시뮬레이션 연결 준비됨"
        case .listening: return "듣기 시뮬레이션 중"
        case .awaitingTranscript: return "예시 인식 결과 대기 중"
        case .generating: return "예시 모델 결과 대기 중"
        case .speaking: return "TTS 응답 시뮬레이션 중"
        case .awaitingNextRound: return "다음 대화 대기 중"
        case .awaitingToolApproval: return "도구 확인 대기 (상태만)"
        case .closed: return "대화 종료됨"
        }
    }
    private var isActive: Bool { ![.disconnected, .idle, .closed].contains(lab.snapshot.phase) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("로직 시뮬레이션 · 오디오 수집, 네트워크, 안경 조작 없음", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.amber).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.98, green: 0.92, blue: 0.77), in: RoundedRectangle(cornerRadius: 14))
                    Card {
                        HStack { Text("음성 대화 흐름").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink); Spacer(); Badge(text: phaseName, active: true) }
                        VStack(spacing: 0) {
                            timelineRow("호출", active: [.idle, .listening].contains(lab.snapshot.phase), complete: [.awaitingTranscript, .generating, .speaking, .awaitingNextRound, .closed].contains(lab.snapshot.phase), last: false)
                            timelineRow("인식", active: [.listening, .awaitingTranscript].contains(lab.snapshot.phase), complete: [.generating, .speaking, .awaitingNextRound].contains(lab.snapshot.phase), last: false)
                            timelineRow("모델 응답", active: [.generating, .speaking].contains(lab.snapshot.phase), complete: lab.snapshot.phase == .awaitingNextRound, last: false)
                            timelineRow("종료", active: lab.snapshot.phase == .awaitingNextRound, complete: lab.snapshot.phase == .closed, last: true)
                        }
                        HStack {
                            Text("대화 차수 \(lab.snapshot.currentRound.map { $0.index + 1 } ?? 0)")
                            Spacer()
                            Text("완료 \(lab.snapshot.completedRoundCount)회")
                        }.font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)
                        Toggle("온라인 시뮬레이션", isOn: Binding(get: { lab.snapshot.networkAvailable }, set: { lab.network($0) }))
                            .font(.subheadline).disabled(isActive)
                        Text("이 앱의 클라우드 우선·로컬 대체 방식을 실험합니다. 공식 앱의 인식 결과가 아니며 휴대폰 네트워크는 변경하지 않습니다.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                        if let source = lab.snapshot.asrSource {
                            Label(source == .local ? "선택한 방식: 로컬 인식" : "선택한 방식: 클라우드 인식", systemImage: source == .local ? "iphone" : "cloud")
                                .font(.caption).foregroundStyle(Palette.green)
                        }
                        if !lab.snapshot.transcript.isEmpty {
                            Text("예시 질문: \(lab.snapshot.transcript)").font(.subheadline).foregroundStyle(Palette.ink)
                        }
                        if !lab.snapshot.response.isEmpty {
                            Text("예시 응답: \(lab.snapshot.response)").font(.subheadline).foregroundStyle(Palette.green)
                        }
                        mainAction
                        if isActive {
                            HStack {
                                Button("응답 중단 시뮬레이션") { lab.interrupt() }.accessibilityIdentifier("lab-interrupt")
                                Spacer()
                                Button("종료 시뮬레이션") { lab.exit() }.accessibilityIdentifier("lab-exit")
                            }.font(.system(size: 13, weight: .medium))
                        }
                        if lab.canTestStale {
                            Button("이전 대화의 지연 응답 입력") { lab.staleCallback() }.font(.caption).accessibilityIdentifier("lab-stale")
                        }
                        if let result = lab.staleCallbackResult { Text(result).font(.caption).foregroundStyle(Palette.green) }
                    }
                    Card {
                        DisclosureGroup("이벤트 기록 (실제 동작 없음)") {
                            if lab.events.isEmpty {
                                Text("시뮬레이션을 시작하면 코어가 반환하는 이벤트를 표시합니다. 오디오, 모델, 도구 또는 Bluetooth 동작은 실행하지 않습니다.")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(5).padding(.top, 10)
                            } else {
                                ForEach(Array(lab.events.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                                }
                            }
                        }.font(.system(size: 13, weight: .medium))
                    }
                    Card {
                        Text("도구 승인 보호").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.green)
                        FeatureRow(icon: "link", title: "요청 연결", subtitle: "실제 도구 요청과 연결 안 됨", status: "실행 안 됨")
                        FeatureRow(icon: "checkmark.shield", title: "유효 기간 확인", subtitle: "발급하거나 사용한 권한 없음", status: "실행 안 됨")
                        FeatureRow(icon: "square.on.square", title: "중복 방지", subtitle: "이벤트만 표시 · 도구 실행 안 함", status: "실행 안 됨")
                    }
                }.padding(24)
            }.background(Palette.background).navigationTitle("프로토콜 실험실").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }

    private func timelineRow(_ title: String, active: Bool, complete: Bool, last: Bool) -> some View {
        HStack(spacing: 15) {
            VStack(spacing: 0) {
                Image(systemName: complete ? "checkmark.circle.fill" : active ? "play.circle.fill" : "circle")
                    .font(.system(size: 21)).foregroundStyle(active || complete ? Palette.green : Palette.muted.opacity(0.5))
                    .frame(height: 27)
                if !last { Rectangle().fill(Palette.line).frame(width: 1, height: 16) }
            }
            Text(title).font(.system(size: 14)).foregroundStyle(active || complete ? Palette.ink : Palette.muted)
            Spacer()
            Text(complete ? "시뮬레이션 완료" : active ? "현재 단계" : "대기 중").font(.system(size: 11)).foregroundStyle(active || complete ? Palette.green : Palette.muted)
        }
    }

    @ViewBuilder private var mainAction: some View {
        switch lab.snapshot.phase {
        case .disconnected: PrimaryButton(title: "연결 시뮬레이션 시작") { lab.connect() }.accessibilityIdentifier("lab-connect")
        case .idle, .closed: PrimaryButton(title: "호출 시뮬레이션") { lab.wake() }.accessibilityIdentifier("lab-wake")
        case .listening, .awaitingTranscript: PrimaryButton(title: "예시 인식 결과 입력") { lab.transcript() }.accessibilityIdentifier("lab-asr")
        case .generating: PrimaryButton(title: "예시 응답 입력 + TTS 시작") { lab.answer() }.accessibilityIdentifier("lab-answer")
        case .speaking: PrimaryButton(title: "TTS 입력 완료 + 재생 종료 시뮬레이션") { lab.finishSpeech() }.accessibilityIdentifier("lab-tts-finish")
        case .awaitingNextRound: PrimaryButton(title: "안경의 다음 대화 시작 시뮬레이션") { lab.nextRound() }.accessibilityIdentifier("lab-next")
        case .awaitingToolApproval:
            Text("도구 확인 대기 · 상태만 표시하며 권한 실행기는 연결되지 않았습니다")
                .font(.caption).foregroundStyle(Palette.amber).accessibilityIdentifier("lab-tool-approval-pending")
        }
    }
}
