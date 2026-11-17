import SwiftUI

struct CodexCompanionView: View {
    @EnvironmentObject private var codex: CodexCompanion
    @EnvironmentObject private var push: CodexPush
    @EnvironmentObject private var notifications: CompanionNotifications
    @Environment(\.scenePhase) private var scenePhase
    @State private var endpoint = ""
    @State private var token = ""
    @State private var voiceTools = false
    @State private var prompt = ""
    @State private var error: String?
    @State private var approval: CodexApproval?
    @State private var answers: [String: String] = [:]
    @State private var confirmRelease = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    Label("내 PC의 Codex를 안경에서", systemImage: "terminal").font(.headline)
                    Text("작업을 보내고 진행 상황을 확인하세요. PC가 독립적으로 실행하므로 음성 연결을 유지할 필요가 없습니다. 승인은 이 화면에서 직접 확인해야 합니다.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text(codex.status).font(.caption).accessibilityIdentifier("codex-status")
                    if let state = codex.state {
                        Text(state.workspace).font(.caption2).textSelection(.enabled)
                        Badge(text: state.readOnly ? "읽기 전용 테스트" : "작업 공간 쓰기 허용")
                    }
                }
                Card {
                    Text("PC 브리지").font(.headline)
                    TextField("HTTPS 주소", text: $endpoint).accessibilityIdentifier("codex-endpoint")
                    SecureField("전용 액세스 토큰 (비우면 기존 값 유지)", text: $token).privacySensitive().accessibilityIdentifier("codex-token")
                    Toggle("DeepSeek의 Codex 도구 호출 허용", isOn: $voiceTools).accessibilityIdentifier("codex-voice-tools")
                    Text("음성으로 지시한 텍스트가 이 PC와 Codex에 전송될 수 있습니다. 마이크 원본 오디오는 업로드하지 않으며 기존 데스크톱 작업은 제어하지 않습니다.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Button("설정 저장 · 작업 시작 안 함") {
                        do { try codex.save(endpoint: endpoint, token: token, voiceTools: voiceTools); token = "" }
                        catch { self.error = error.localizedDescription; token = "" }
                    }.disabled(codex.busy || codex.hasUnknownDelivery).accessibilityIdentifier("codex-save")
                    Button("연결 / 상태 새로고침") { Task { await codex.refresh() } }
                        .disabled(!codex.configured).accessibilityIdentifier("codex-refresh")
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                Card {
                    Toggle("Codex 완료 및 확인 요청 알림", isOn: Binding(get: { push.enabled }, set: { push.setEnabled($0) }))
                        .accessibilityIdentifier("codex-push-enabled")
                    Text(push.status).font(.caption).accessibilityIdentifier("codex-push-status")
                    Text(notifications.testStatus).font(.caption2).accessibilityIdentifier("codex-push-delivery")
                    NavigationLink("안경 알림 설정 및 전송 테스트") { NotificationCenterView() }
                    Text("새 이벤트만 알립니다. 안경에는 요약을 표시하고 전체 내용은 이 화면에서 확인합니다. 음성·녹음·프롬프터 사용 중에는 기다립니다. 알림은 승인이 아닙니다.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text("안경 알림이 허용되어 있으면 연결 후 전체 알림 설정을 복원합니다. 다른 앱의 필터는 대체하지 않습니다.")
                        .font(.caption2).foregroundStyle(Palette.muted)
                    Text("앱이 실행 가능한 동안 약 2초마다 확인합니다. APNs를 사용하지 않아 앱 중지 후 즉시 알림을 보장하지 않습니다. 브리지는 최대 128개 이벤트를 보관하며 완료 이벤트는 1시간 후 만료되고 재시작 시 지워집니다.")
                        .font(.caption2).foregroundStyle(Palette.muted)
                }
                if codex.hasUnknownDelivery {
                    Card {
                        Label("이전 요청 결과 확인 필요", systemImage: "exclamationmark.triangle").foregroundStyle(Palette.amber)
                        Text("동일한 요청 ID를 유지하며 중복 작업을 만들지 않습니다. 네트워크 복구 후 결과를 확인하세요. 확인 대기 내용은 기기에 임시 저장 후 삭제됩니다.")
                            .font(.caption)
                        Button("이전 요청 확인") { Task { await codex.retryPending() } }.disabled(codex.busy)
                        if let cause = codex.lastDeliveryError { Text(cause).font(.caption).foregroundStyle(Palette.amber) }
                        Text("이 상태에서는 새 전송과 작업 전환이 잠깁니다. 아래 답변은 마지막으로 조회한 내용이며 새 요청의 응답이 아닐 수 있습니다.").font(.caption)
                        Button("PC 작업 확인 후 전송 보류 해제") { confirmRelease = true }
                            .disabled(codex.busy).accessibilityIdentifier("codex-release-pending")
                    }
                }
                Card {
                    HStack {
                        Text("현재 작업").font(.headline); Spacer()
                        Button("새 작업으로 전환") { codex.select(nil) }.disabled(codex.busy || codex.hasUnknownDelivery)
                    }
                    Text(codex.selectedTaskID.map { "작업 " + String($0.prefix(8)) } ?? "다음 메시지는 새 작업을 만듭니다").font(.caption)
                    if codex.busy { Text("요청을 전송하고 접수 결과를 기다리고 있습니다. 완료 전에는 작업을 전환할 수 없습니다.").font(.caption).foregroundStyle(Palette.amber) }
                    TextField("Codex에 요청할 내용…", text: $prompt, axis: .vertical).lineLimit(2...6).accessibilityIdentifier("codex-prompt")
                    Button("무작위 연결 테스트 입력") {
                        prompt = "Turbo IO 연결 테스트입니다. 파일이나 도구를 사용하지 말고 다음 문구만 응답하세요: Turbo IO Codex 확인 " + String(UUID().uuidString.prefix(6))
                    }.accessibilityIdentifier("codex-fixture")
                    HStack {
                        Button("PC로 전송") { Task { do { _ = try await codex.message(prompt); prompt = "" } catch { self.error = error.localizedDescription } } }
                            .disabled(!codex.configured || codex.busy || codex.hasUnknownDelivery || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("codex-send")
                        Spacer()
                        Button("작업 중지", role: .destructive) { Task { do { try await codex.stop() } catch { self.error = error.localizedDescription } } }
                            .disabled(codex.selected?.turnId == nil || codex.busy || codex.hasUnknownDelivery)
                    }
                }
                if let task = codex.selected {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(task.status).font(.headline)
                        Text(task.answer.isEmpty ? "아직 Codex 응답이 없습니다" : task.answer).textSelection(.enabled).privacySensitive()
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Palette.mint)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 20)).accessibilityIdentifier("codex-output")
                    ForEach(task.pending) { request in
                        Card {
                            Label(request.kind == "question" ? "Codex가 답변을 요청했습니다" : "Codex가 개별 승인을 요청했습니다", systemImage: "hand.raised").font(.headline)
                            Text(request.summary).font(.caption).textSelection(.enabled)
                            Text("요청 \(request.id.prefix(8)) · 2분간 유효").font(.caption2)
                            if request.kind == "question" {
                                ForEach(request.questions) { q in
                                    Text(q.question).font(.subheadline)
                                    ForEach(q.options, id: \.self) { option in Button(option) { answers[q.id] = option } }
                                    TextField("내 답변", text: Binding(get: { answers[q.id] ?? "" }, set: { answers[q.id] = $0 }))
                                }
                                Button("답변 제출") { decide(request, accept: false) }
                                    .disabled(codex.busy || request.questions.contains(where: { answers[$0.id, default: ""].isEmpty }))
                            } else {
                                HStack {
                                    Button("이번 요청 승인") { approval = request }
                                    Button("거부", role: .destructive) { decide(request, accept: false) }
                                }.disabled(codex.busy || codex.hasUnknownDelivery)
                            }
                        }
                    }
                }
                if let tasks = codex.state?.tasks, !tasks.isEmpty {
                    Card {
                        Text("브리지에서 관리하는 작업").font(.headline)
                        ForEach(tasks) { task in
                            Button("\(task.id.prefix(8)) · \(task.status)") { codex.select(task.id) }
                                .disabled(codex.busy || codex.hasUnknownDelivery)
                        }
                    }
                }
                Text("화면이 열려 있으면 2초마다 갱신합니다. 화면을 닫아도 PC 작업은 계속됩니다. iOS 백그라운드 실시간 알림은 보장하지 않습니다. 음성으로 Codex 진행 상황을 물어볼 수 있습니다.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(22)
        }.background(Palette.background).navigationTitle("Codex 콘솔").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("아이폰의 전송 보류만 해제할까요?", isPresented: $confirmRelease) {
                Button("PC 작업을 확인했으며 전송 보류 해제", role: .destructive) { codex.releaseUnconfirmedDelivery() }
            } message: {
                Text("PC에서 이미 실행된 작업은 취소되지 않습니다. PC 콘솔이나 작업 목록에서 기존 요청의 처리 여부를 확인하세요. 같은 내용을 다시 보내면 중복 실행될 수 있습니다. 해제 자체는 새 요청을 보내지 않습니다.")
            }
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .onAppear { endpoint = codex.endpoint; voiceTools = codex.voiceToolsEnabled }
            .task {
                while !Task.isCancelled {
                    if scenePhase == .active { await codex.refresh() }
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
                }
            }
            .confirmationDialog("이 요청만 승인하며 전체 세션 권한을 허용하지 않습니다.", isPresented: Binding(get: { approval != nil }, set: { if !$0 { approval = nil } })) {
                Button("이번 요청 승인 확인") { if let request = approval { decide(request, accept: true) }; approval = nil }
            } message: { Text(approval?.summary ?? "") }
            .alert("Codex 브리지", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("확인", role: .cancel) {}
            } message: { Text(error ?? "") }
    }
    private func decide(_ request: CodexApproval, accept: Bool) {
        Task { do { try await codex.decide(request, approve: accept, answers: answers); answers = [:] } catch { self.error = error.localizedDescription } }
    }
}
