import SwiftUI

struct ConversationView: View {
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @EnvironmentObject private var timeline: ConversationTimeline
    @State private var showKeys = false
    @State private var showConfiguration = false
    @State private var showSimulation = false
    @State private var showDiagnostics = false
    @State private var useCloud = true
    @State private var continuous = true
    @State private var confirmStart = false
    var body: some View {
        Screen(title: "음성 대화", eyebrow: "클라우드 음성 인식 · 스트리밍 대화") {
            HStack {
                Label(runtime.phaseLabel, systemImage: runtime.enabled ? "waveform" : "moon")
                    .font(.system(size: 16, weight: .semibold))
                Spacer(); Badge(text: runtime.supportsDevice ? (runtime.ready ? "인증 완료" : "연결 안 됨") : "시뮬레이터 미리보기")
            }.foregroundStyle(Palette.ink).padding(16).background(Palette.mint.opacity(0.2), in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 18) {
                Label("내가 한 말", systemImage: "mic").font(.caption).foregroundStyle(Palette.mint.opacity(0.7))
                Text(runtime.transcript.isEmpty ? "음성 호출 후 인식된 내용이 여기에 표시됩니다" : runtime.transcript)
                    .font(.system(size: 18)).foregroundStyle(.white).privacySensitive()
                Divider().overlay(Palette.mint.opacity(0.3))
                Label("DeepSeek Flash", systemImage: "sparkles").font(.caption).foregroundStyle(Palette.mint.opacity(0.7))
                Text(runtime.answer.isEmpty ? "응답이 실시간으로 표시됩니다. 말하면 응답을 중단할 수 있습니다" : runtime.answer)
                    .font(.system(size: 16)).foregroundStyle(Palette.mint).lineSpacing(6).privacySensitive()
                if runtime.modelComplete { Text("모델 출력 완료 · 안경 표시 완료는 별도 확인").font(.caption2).foregroundStyle(Palette.mint.opacity(0.6)) }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("live-voice-content")
            if !runtime.enabled {
                Text("마이크 꺼짐 · 전송 중인 오디오 없음").font(.caption).foregroundStyle(Palette.muted)
            } else {
                Text(runtime.phase == "idle" || runtime.phase == "waitingForConnection" ? "음성 호출을 기다리는 상태이며 상시 녹음하지 않습니다." : "오디오 처리 중입니다. 음성 대기를 끄면 현재 처리와 자동 응답을 중지합니다.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            NavigationLink("외부 AI 연결 방법과 기능별 차이") { ExternalServicesView() }
                .font(.subheadline).accessibilityIdentifier("voice-services-guide")
            HStack {
                Button("음성 AI 연결 설정") { if runtime.supportsDevice { showKeys = true } else { showConfiguration = true } }.accessibilityIdentifier("model-settings")
                Spacer()
                Button("로컬 동작 데모") { showSimulation = true }.accessibilityIdentifier("open-session-lab")
            }.font(.subheadline)
            NavigationLink { CodexCompanionView() } label: {
                Label("Codex 작업 및 승인", systemImage: "terminal")
            }.accessibilityIdentifier("codex-conversation-entry")
            NavigationLink { ModelToolsView() } label: {
                Label("AI 도구 · 모델이 사용할 수 있는 도구", systemImage: "wrench.and.screwdriver")
            }.accessibilityIdentifier("model-tools-conversation-entry")
            if let error = timeline.storageError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.amber)
            }
            NavigationLink { ConversationTimelineView() } label: {
                Card { FeatureRow(icon: "clock.arrow.circlepath", title: "대화 기록", subtitle: "기기에서 대화 기록 · 내보내기 및 공유", status: "기기에 저장", active: true) }
            }.buttonStyle(.plain).accessibilityIdentifier("conversation-timeline")
            Card {
                Text("검증된 음성 서비스 조합").font(.headline).foregroundStyle(Palette.ink)
                FeatureRow(icon: "waveform", title: "Alibaba Cloud 스트리밍 ASR", subtitle: "클라우드 VAD 사용 · 로컬 무음 감지와 중복하지 않음", status: "프로토타입 검증됨")
                Text("인식 언어 힌트: 한국어·영어. 자동 언어 판별의 오인식을 줄이기 위한 설정이며 다른 언어를 완전히 차단하지는 않습니다.")
                    .font(.caption).foregroundStyle(Palette.muted)
                Divider().overlay(Palette.line)
                FeatureRow(icon: "bolt", title: "DeepSeek V4 Flash", subtitle: "추론 모드 꺼짐 · 스트리밍 텍스트 · 기본 검색 없음", status: "프로토타입 검증됨")
                Divider().overlay(Palette.line)
                Text("호출된 대화 중에는 ASR 연결이 유지됩니다. 새 문장이 인식되면 이전 응답을 중단하며 빈 문장은 무시합니다. 세션 제한은 120초입니다. Codex 도구는 별도 설정과 허용이 필요하며 이 경로는 TTS를 지원하지 않습니다.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            if runtime.supportsDevice {
                Button(runtime.testingModel ? "DeepSeek 연결 테스트 중…" : "DeepSeek 연결 테스트") { runtime.testModelConnection() }
                    .disabled(runtime.testingModel || !runtime.hasCredentials)
                Text("연결 테스트는 짧은 고정 문장만 DeepSeek에 전송하며 소액의 API 요금이 발생합니다. 마이크는 사용하지 않습니다.")
                    .font(.caption).foregroundStyle(Palette.muted)
                if !runtime.modelTestResult.isEmpty {
                    Text(runtime.modelTestResult).font(.caption).foregroundStyle(Palette.ink)
                        .accessibilityIdentifier("model-connection-test-result")
                }
                Card {
                    Toggle("클라우드 AI 대화 사용", isOn: $useCloud).disabled(runtime.enabled)
                    Toggle("연속 음성 인식 · 끼어들기 허용", isOn: $continuous).disabled(runtime.enabled || !useCloud).accessibilityIdentifier("voice-continuous-draft")
                    Text(runtime.enabled ? (runtime.cloud && runtime.continuous ? "실행 중: 연속 ASR · 새 문장 인식 시 응답 중단" : "실행 중: 단일 인식 모드 · 응답 중 끼어들기 미보장") : "위 설정은 다음 실행에 적용됩니다. 현재 실행 중이 아닙니다")
                        .font(.caption).foregroundStyle(Palette.amber).accessibilityIdentifier("voice-effective-policy")
                    Text(useCloud ? "호출 후 오디오는 설정한 Alibaba Cloud ASR로, 인식 텍스트는 DeepSeek로 전송됩니다. 서비스 요금이 발생할 수 있습니다." : "로컬 WebRTC VAD 테스트만 합니다. 무작위 테스트 문자를 표시하며 음성 인식이나 업로드는 하지 않습니다.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Button(runtime.hasCredentials ? "음성 서비스 API 키 관리" : "ASR 및 모델 API 키 설정") { showKeys = true }
                        .disabled(runtime.enabled)
                }
                if runtime.enabled {
                    PrimaryButton(title: "음성 대기 끄기", icon: "stop.circle") { runtime.stop() }
                    Button("현재 대화 종료 · 대기 유지") { runtime.endRound() }
                } else {
                    PrimaryButton(title: "안경 음성 대기 켜기", icon: "waveform", enabled: runtime.ready && (!useCloud || runtime.hasCredentials)) { confirmStart = true }
                }
                Button("연결 및 등록 해제 관리") { showDiagnostics = true }
                Text(runtime.latestEvent).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
            } else {
                Text("이 빌드는 안경 통신과 클라우드 서비스를 사용하지 않습니다. 실제 기기는 RayNeoCompanionDevice 빌드를 사용하세요. 데모는 실제 오디오 수집이 아닙니다.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Text("응답과 완료 메시지 전송 후 10초간 새 문장이 없으면 자동 종료됩니다. 다시 말하면 타이머가 초기화됩니다. 전송 완료와 안경 표시 완료는 다릅니다.")
                .font(.caption).foregroundStyle(Palette.amber)
            Button("현재 화면의 텍스트 지우기") { runtime.clearText() }.font(.caption)
        }
        .onAppear { runtime.prepare(); reflectRunningPolicy() }
        .onChange(of: runtime.enabled) { _ in reflectRunningPolicy() }
        .onChange(of: runtime.cloud) { _ in reflectRunningPolicy() }
        .onChange(of: runtime.continuous) { _ in reflectRunningPolicy() }
        .sheet(isPresented: $showConfiguration) { ModelConfigurationView() }
        .sheet(isPresented: $showSimulation) { SessionSimulationView() }
        .sheet(isPresented: $showKeys) { LiveVoiceKeysView() }
        #if COMPANION_DEVICE
        .sheet(isPresented: $showDiagnostics, onDismiss: { runtime.refresh() }) {
            NavigationStack { VoiceDiagnosticsView(runtime: runtime).toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { showDiagnostics = false } } } }
        }
        #endif
        .confirmationDialog(useCloud ? "음성 호출 시 오디오는 Alibaba Cloud로, 텍스트는 DeepSeek로 전송됩니다. 요금이 발생할 수 있습니다." : "로컬 무작위 응답 테스트를 시작합니다. 음성은 업로드하지 않습니다.", isPresented: $confirmStart) {
            Button("음성 대기 켜기 확인") { runtime.start(cloud: useCloud, continuous: continuous) }
        }
        .alert("음성 서비스", isPresented: Binding(get: { runtime.error != nil }, set: { if !$0 { runtime.error = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(runtime.error ?? "") }
    }
    private func reflectRunningPolicy() {
        guard runtime.enabled else { return }
        useCloud = runtime.cloud; continuous = runtime.continuous
    }
}

struct LiveVoiceKeysView: View {
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @Environment(\.dismiss) private var dismiss
    @State private var asr = ""
    @State private var host = CloudASRHostSettings.current()
    @State private var llm = ""
    @State private var enableDefault = true
    var body: some View {
        NavigationStack {
            Form {
                Section("실제 음성 대화에 사용하는 서비스") {
                    Text("ASR는 말을 글로 바꾸고, DeepSeek는 그 글에 답합니다. 두 서비스는 별도 계정·키가 필요합니다. 다른 모델 설정 초안은 이 경로에 적용되지 않습니다.").font(.subheadline)
                    Text("Alibaba Cloud qwen-audio-3.0-asr-flash-streaming\nDeepSeek V4 Flash · 추론 꺼짐 · 스트리밍")
                    Text("지원 모델과 DashScope 스트리밍 프로토콜을 제공하는 본인의 Alibaba Cloud ASR 호스트를 입력하세요. DeepSeek는 공식 고정 주소를 사용하며 다른 모델 설정은 초안입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("이 앱 전용 키체인") {
                    TextField("ASR 호스트명 (https:// 제외)", text: $host)
                        .accessibilityIdentifier("live-asr-host").keyboardType(.URL)
                    Text("호스트를 바꾸면 다른 호스트의 키를 재사용하지 않습니다. 소스에 개발자의 주소나 API 키는 포함되지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("Alibaba Cloud API 키 (비우면 기존 값 유지)", text: $asr)
                        .accessibilityIdentifier("live-asr-key")
                    SecureField("DeepSeek API 키 (비우면 기존 값 유지)", text: $llm)
                        .accessibilityIdentifier("live-llm-key")
                    Text("공식 앱이나 테스트 앱의 키는 읽지 않습니다. 첫 잠금 해제 후 백그라운드 음성 기능에서 사용할 수 있으며 동기화하거나 원래 값을 표시하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                Toggle("저장 후 클라우드 대화와 연속 인식을 기본으로 켜기", isOn: $enableDefault).accessibilityIdentifier("live-default-voice")
                Text("기본 음성 대기는 연결 후 호출만 기다리며 상시 녹음하지 않습니다. 수동으로 끄면 자동으로 다시 켜지지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(enableDefault ? "저장하고 기본 음성 대기 켜기" : "API 키만 저장 · 대화 시작 안 함") {
                    let saved = runtime.saveKeys(asr: asr, llm: llm, host: host, enableDefault: enableDefault)
                    asr = ""; llm = ""
                    if saved { dismiss() }
                }.accessibilityIdentifier("live-save-keys")
                if let error = runtime.error { Text(error).foregroundStyle(.red).font(.caption) }
            }.navigationTitle("음성 AI 연결 설정").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
    }
}
