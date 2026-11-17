import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject private var notifications: CompanionNotifications
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @State private var confirmSources = false
    var body: some View {
        Form {
            Section {
                Text("안경에서 확인하는 알림").font(.title3.weight(.semibold))
                Text("시스템 알림 공유와 사용자 알림은 별도 기능입니다. 이 화면은 다른 앱의 알림 본문을 수집하지 않습니다.").font(.caption).foregroundStyle(Palette.muted)
                Text(voice.ready ? "안경 연결됨" : "안경 연결 안 됨 · 초안 편집 및 미리보기 가능")
                    .accessibilityIdentifier("notification-connection")
            }
            Section("시스템 알림 공유 · ANCS") {
                Toggle("안경 알림 허용", isOn: Binding(get: { notifications.preferences.enabled }, set: { notifications.setEnabled($0) }))
                    .accessibilityIdentifier("notification-master")
                Text("연결된 안경이 사용 중이 아니면 전체 설정을 즉시 전송합니다. 오프라인에서는 초안만 저장하며 iOS 알림 권한은 변경하지 않습니다.").font(.caption).foregroundStyle(Palette.muted)
                Button("현재 안경에 전체 알림 설정 적용") { notifications.applyMaster() }
                    .disabled(!notifications.canSend).accessibilityIdentifier("notification-apply-master")
                NavigationLink { NotificationSourcesView() } label: {
                    LabeledContent("허용할 앱", value: "\(notifications.preferences.sources.filter(\.allowed).count)/\(notifications.preferences.sources.count)")
                }.accessibilityIdentifier("notification-sources-open")
                Picker("알림 표시 시간", selection: Binding(get: { notifications.preferences.displayTime }, set: { notifications.setDisplayTime($0) })) {
                    ForEach([5,10,15,20,30], id: \.self) { seconds in Text("\(seconds)초").tag(seconds) }
                }.accessibilityIdentifier("notification-display-time")
                Button("15초로 설정 (초안)") { notifications.setDisplayTime(15) }
                    .accessibilityIdentifier("notification-duration-15")
                Text("표시 시간은 안경에서 확인하세요. 시간과 앱 필터를 함께 전송하므로 적용 전에 허용할 앱을 확인하세요. 초안 변경만으로는 전송하지 않습니다.")
                    .font(.caption).foregroundStyle(Palette.muted)
                Text(notifications.sourcesNeedApply ? "앱 목록: 초안 적용 대기" : "앱 목록: 전송됨 · 실제 동작 확인 필요")
                    .font(.caption).accessibilityIdentifier("notification-sources-state")
                Button("앱별 알림 설정 적용") { confirmSources = true }
                    .disabled(!notifications.canSend).accessibilityIdentifier("notification-apply-sources")
                Text(notifications.configurationStatus).font(.caption).accessibilityIdentifier("notification-settings-status")
                if let enabled = notifications.reportedEnabled {
                    Text("안경의 전체 알림 상태: \(enabled ? "켜짐" : "꺼짐") (앱별 확인 응답 아님)").font(.caption)
                }
            }
            Section("수동 테스트 · 서버 연결 없음") {
                NavigationLink { NotificationTestView() } label: {
                    Label("테스트 알림 작성 및 전송", systemImage: "paperplane")
                }.accessibilityIdentifier("notification-test-open")
                Text("안경으로 직접 보내며 휴대폰에는 알림을 띄우지 않습니다. 제목과 본문을 입력하고 UID, 상태, 시간 초과를 확인할 수 있습니다.").font(.caption).foregroundStyle(Palette.muted)
            }
            Section("알림 공유 확인") {
                Text(notifications.availabilityStatus).accessibilityIdentifier("notification-ancs-status")
                Button("안경 ANCS 상태 조회") { notifications.queryAvailability() }
                    .disabled(!notifications.canSend).accessibilityIdentifier("notification-query")
                Text("iPhone 설정 → Bluetooth → 안경 상세에서 시스템 알림 공유를 허용하세요. 원본 앱에도 알림 권한이 필요합니다. 집중 모드와 미리보기 설정이 표시에 영향을 줄 수 있으며 Turbo IO가 이를 변경하지 않습니다.").font(.caption).foregroundStyle(Palette.muted)
            }
            if let error = notifications.error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("notification-error") } }
        }
        .navigationTitle("알림 센터").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .preference(key: CompanionTabBarHiddenPreference.self, value: true)
        .onAppear { features.prepare(); notifications.connectionChanged() }
        .onChange(of: voice.deviceID) { _ in notifications.connectionChanged() }
        .confirmationDialog("현재 안경의 앱별 알림 설정을 대체할까요?", isPresented: $confirmSources, titleVisibility: .visible) {
            Button("현재 설정 적용 확인") { notifications.applySources() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("전체 알림, 목록의 앱별 허용(전화 포함), 표시 시간 초안을 적용합니다: displayTime=\(notifications.preferences.displayTime)、avoidDuplicate=false、intervalTime=2. 안경에서 읽은 기존 설정이 아니며 목록에 없는 앱의 차단은 보장하지 않습니다.")
        }
    }
}

struct NotificationSourcesView: View {
    @EnvironmentObject private var notifications: CompanionNotifications
    @State private var search = ""
    @State private var adding = false
    private var visible: [NotificationSource] {
        notifications.preferences.sources.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            Section {
                Text("이 목록은 설정 가능한 알림 출처이며 설치된 앱 목록이 아닙니다. 알 수 없는 앱을 자동 차단하지 않습니다. 처음 적용하면 기존 앱 필터를 대체합니다.")
                    .font(.caption).accessibilityIdentifier("notification-source-boundary")
                TextField("이름 또는 Bundle ID 검색", text: $search)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("notification-source-search")
                Button("알림 앱 추가") { adding = true }.accessibilityIdentifier("notification-source-add")
            }
            Section("켜짐은 허용 · 수정 후 이전 화면에서 적용") {
                ForEach(visible) { source in
                    Toggle(isOn: Binding(get: { notifications.preferences.sources.first(where: { $0.id == source.id })?.allowed ?? false },
                                         set: { notifications.setAllowed(source.id, $0) })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.displayName)
                            Text(source.id).font(.caption2).foregroundStyle(Palette.muted)
                        }
                    }.accessibilityIdentifier("notification-source-\(source.id)")
                }
            }
            Section { Text("정확한 Bundle ID를 입력해야 필터가 작동합니다. 다른 앱의 데이터를 읽거나 알림을 자동 업로드하지 않습니다. 차단을 해제하려면 항목을 켜고 설정을 적용하세요.").font(.caption) }
        }
        .navigationTitle("허용할 앱").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .preference(key: CompanionTabBarHiddenPreference.self, value: true)
        .sheet(isPresented: $adding) { NotificationSourceEditor() }
    }
}

private struct NotificationSourceEditor: View {
    @EnvironmentObject private var notifications: CompanionNotifications
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var id = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("앱 이름", text: $name).accessibilityIdentifier("notification-source-name")
                TextField("Bundle ID (예: com.example.app)", text: $id)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("notification-source-id")
                Text("표시 이름이 아닌 실제 Bundle ID를 입력하세요. 새 항목은 기본 허용되며 저장 후 이전 화면에서 설정을 적용해야 합니다.").font(.caption)
                if let error = notifications.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("알림 출처 추가").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("알림 앱 저장") { if notifications.addSource(name: name, id: id) { dismiss() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !GlassesNotificationProtocol.validAppID(id))
                        .accessibilityIdentifier("notification-source-save")
                }
            }
        }
    }
}

struct NotificationTestView: View {
    @EnvironmentObject private var notifications: CompanionNotifications
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var title = "Turbo IO 알림 테스트"
    @State private var content = "독립 앱의 사용자 알림 테스트입니다."
    @FocusState private var focused: Bool
    private var valid: Bool { (try? GlassesNotificationProtocol.notification(uid: "1", title: title, content: content)) != nil }
    var body: some View {
        Form {
            Section("테스트 내용 편집") {
                Text("출처는 Turbo IO로 고정됩니다. 내용은 현재 화면에만 유지되며 저장하거나 서버에 업로드하지 않습니다.").font(.caption).foregroundStyle(Palette.muted)
                TextField("제목 (최대 80자)", text: $title, axis: .vertical)
                    .focused($focused).accessibilityIdentifier("notification-test-title")
                TextField("본문 (최대 500자)", text: $content, axis: .vertical).lineLimit(3...8)
                    .focused($focused).accessibilityIdentifier("notification-test-content")
                Text("제목 \(title.count)/80 · 본문 \(content.count)/500 · 테스트 한도이며 안경 레이아웃을 보장하지 않습니다").font(.caption2)
                Button("무작위 확인 코드 입력") {
                    let code = String(UUID().uuidString.prefix(6))
                    title = "Turbo IO 알림 테스트 \(code)"; content = "첫째 줄: 사용자 알림\n둘째 줄: 확인 코드 \(code)\n안경의 텍스트를 확인하세요."
                    focused = false
                }.accessibilityIdentifier("notification-test-sample")
            }
            Section("휴대폰 미리보기 · 안경 스크린샷 아님") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Turbo IO", systemImage: "bell.badge").font(.caption).foregroundStyle(Palette.green)
                    Text(title).font(.headline)
                    Text(content).font(.body)
                }.padding(.vertical, 8).accessibilityIdentifier("notification-test-preview")
            }
            Section {
                Button("안경으로 전송") {
                    focused = false; _ = notifications.send(title: title, content: content)
                }.disabled(!notifications.canTest || !valid).accessibilityIdentifier("notification-test-send")
                Text("연결 인증 후 안경 알림과 Turbo IO 출처를 허용하고 전체 설정을 적용하세요. 음성·녹음·프롬프터 사용 중에는 보내지 않습니다. 한 번만 전송하며 자동 재시도하지 않습니다.").font(.caption).foregroundStyle(Palette.muted)
                if let uid = notifications.lastUID { Text("최근 UID: \(uid)").font(.caption.monospaced()).accessibilityIdentifier("notification-test-uid") }
                Text(notifications.testStatus).accessibilityIdentifier("notification-test-status")
                if let operation = notifications.operationStatus { Text(operation).font(.caption) }
                if let error = notifications.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("notification-test-error") }
                Text("SDK 반환값, 안경의 상태 응답, 실제 화면 표시는 별개입니다. 응답이 있어도 안경에서 위 확인 코드를 확인하세요. 기존 음성 텍스트 표시는 이 테스트 결과가 아닙니다.").font(.caption)
            }
        }
        .navigationTitle("사용자 알림 테스트").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("편집 완료") { focused = false } } }
        .preference(key: CompanionTabBarHiddenPreference.self, value: true)
        .onChange(of: voice.deviceID) { _ in notifications.connectionChanged() }
    }
}
