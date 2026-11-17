import SwiftUI
import RayNeoSession

struct LegacyConversationView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var showConfiguration = false
    @State private var showSimulation = false

    var body: some View {
        Screen(title: "음성 대화", eyebrow: "음성 인식 및 대화") {
            HStack {
                Label("연결 대기 중", systemImage: "clock").font(.system(size: 16, weight: .semibold))
                Spacer(); Badge(text: "오디오 수집 안 함", active: true)
            }.foregroundStyle(Palette.ink).padding(16).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 17))

            VStack(spacing: 13) {
                Text("목소리로 나의 AI와 연결").font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                Text("인식 · 대화 · 응답").font(.system(size: 13)).foregroundStyle(Palette.mint.opacity(0.7))
                HStack(spacing: 4) {
                    ForEach(0..<39) { index in
                        let height = Double([5, 8, 14, 25, 38, 27, 17, 9, 20, 30, 42, 24, 16][index % 13])
                        Capsule().fill(Palette.mint.opacity(0.35 + Double(index % 4) * 0.1)).frame(width: 3, height: height)
                    }
                }.frame(height: 65).padding(.top, 21).accessibilityLabel("정적인 음성 일러스트 · 오디오 수집 안 함")
                Text("마이크 꺼짐 · 전송 중인 오디오 없음").font(.system(size: 10)).foregroundStyle(Palette.mint.opacity(0.55))
            }.padding(.vertical, 35).frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [Palette.ink, Color(red: 0.10, green: 0.24, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))

            Card {
                Button { showConfiguration = true } label: {
                    HStack {
                        Label("음성 인식 서비스", systemImage: "waveform").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
                        Spacer(); Text("실제 테스트 후 결정").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                    }
                }.buttonStyle(.plain)
                Divider().overlay(Palette.line)
                Button { showConfiguration = true } label: {
                    HStack {
                        Label("모델 서비스", systemImage: "server.rack").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
                        Spacer(); Text(store.configuration.endpoint.isEmpty ? "설정 안 됨" : "기기에 저장됨").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                    }
                }.buttonStyle(.plain)
            }
            PrimaryButton(title: "모델 설정", icon: "gearshape") { showConfiguration = true }.accessibilityIdentifier("model-settings")
            Button { showSimulation = true } label: {
                Label("로컬 동작 데모", systemImage: "play")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity).padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.green, lineWidth: 1))
            }.accessibilityIdentifier("open-session-lab")
        }
        .sheet(isPresented: $showConfiguration) { ModelConfigurationView() }
        .sheet(isPresented: $showSimulation) { SessionSimulationView() }
    }

}

struct ModelConfigurationView: View {
    @EnvironmentObject private var store: CompanionStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ModelConfiguration()
    @State private var key = ""
    @State private var hasKey = false
    @State private var error: String?
    @State private var confirmRemoval = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("초안 저장 전용 · 실제 AI 연결에는 적용되지 않습니다", systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(Palette.green).padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    NavigationLink("실제로 사용할 AI 서비스 설정 방법") { ExternalServicesView() }
                    Card {
                        Text("서비스 주소").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                        TextField("HTTPS 기본 주소 (선택 사항)", text: $draft.endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(13).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("model-endpoint")
                        Text("모델 이름").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                        TextField("모델 이름 입력", text: $draft.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(13).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("model-name")
                        Text("API 키").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                        SecureField(hasKey ? "새 API 키 (비워 두면 기존 키 유지)" : "키체인에 안전하게 저장 (선택 사항)", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(13).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).privacySensitive()
                        Text(hasKey ? "이 서비스의 API 키가 저장되어 있습니다. 원래 값은 표시하지 않습니다." : "API 키는 서비스 주소별로 구분하여 저장합니다.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    }
                    Card {
                        HStack {
                        Text("음성 인식 방식").foregroundStyle(Palette.ink).accessibilityIdentifier("recognition-strategy-label")
                        Spacer()
                        Picker("음성 인식 방식", selection: $draft.recognition) {
                            Text("실제 테스트 후 결정").tag("待实测决定")
                            Text("로컬 Sherpa (준비 중)").tag("本地 Sherpa")
                            Text("사용자 클라우드 (준비 중)").tag("自有云端")
                        }.labelsHidden().accessibilityLabel("음성 인식 방식")
                        }
                        Divider().overlay(Palette.line)
                        HStack {
                        Text("음성 출력").foregroundStyle(Palette.ink).accessibilityIdentifier("speech-output-label")
                        Spacer()
                        Picker("음성 출력", selection: $draft.speech) {
                            Text("연동 준비 중").tag("待接入")
                            Text("시스템 음성 (준비 중)").tag("系统语音")
                            Text("사용자 TTS (준비 중)").tag("自有 TTS")
                        }.labelsHidden().accessibilityLabel("음성 출력")
                        }
                    }.font(.system(size: 14))
                    PrimaryButton(title: "설정 저장", icon: "square.and.arrow.down") { save() }.accessibilityIdentifier("save-model")
                    Label("공식 앱 계정이나 클라우드 자격 증명을 사용하지 않습니다", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(Palette.amber).padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14))
                    Text("API 키는 잠금 해제 후 이 기기에서만 사용하며 로그나 설정 파일에 기록하지 않습니다. 이 페이지의 인식·음성 설정은 초안이며 실제 음성 서비스를 바꾸지 않습니다.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    if hasKey { Button("이 서비스의 저장된 API 키 삭제", role: .destructive) { confirmRemoval = true }.font(.footnote) }
                }.padding(24)
            }.background(Palette.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle("다른 모델 설정 초안").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            }
            .onAppear { draft = store.configuration; hasKey = CredentialVault.hasKey(for: draft.endpoint) }
            .onChange(of: draft.endpoint) { _ in hasKey = CredentialVault.hasKey(for: draft.endpoint) }
            .confirmationDialog("Turbo IO에 저장된 API 키만 삭제합니다. 공식 앱에는 영향이 없습니다.", isPresented: $confirmRemoval) {
                Button("기기에 저장된 API 키 삭제", role: .destructive) {
                    do { try CredentialVault.remove(for: draft.endpoint); hasKey = false } catch { self.error = error.localizedDescription }
                }
            }
            .alert("설정을 저장하지 못함", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("확인", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        do { try store.saveConfiguration(draft, key: key); key = ""; dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
