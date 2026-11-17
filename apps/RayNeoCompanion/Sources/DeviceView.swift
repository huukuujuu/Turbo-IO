import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @EnvironmentObject private var automaticWeather: AutomaticWeather
    @EnvironmentObject private var qweather: QWeatherDashboard
    @State private var showSettings = false
    @State private var showConnection = false

    var body: some View {
        Screen(title: "내 안경", eyebrow: "Turbo IO · 개인 스마트 안경 도우미", headerIcon: "gearshape", headerAction: { showSettings = true }) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("RayNeo iO").font(.system(size: 25, weight: .semibold))
                    Spacer()
                    if store.demoMode { Badge(text: "데모 화면", active: true) }
                }
                Text(runtime.ready ? "인증된 연결" : "연결 안 됨").font(.system(size: 15, weight: .medium))
                GlassesIllustration().padding(.horizontal, 15).padding(.vertical, 28)
                Text("안경 일러스트 · 실시간 기기 상태 아님").font(.system(size: 9)).foregroundStyle(Palette.mint.opacity(0.5))
            }
            .padding(22).foregroundStyle(.white)
            .background(LinearGradient(colors: [Palette.ink, Color(red: 0.10, green: 0.24, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))

            if runtime.supportsDevice {
                PrimaryButton(title: "페어링 중인 안경 검색", icon: "antenna.radiowaves.left.and.right", enabled: !runtime.enabled) { runtime.discover() }
                Button("검색된 안경 연결") { runtime.connect() }.disabled(runtime.enabled)
                Button("이 앱에 등록된 안경 다시 연결") { runtime.reconnectBonded() }
                    .accessibilityIdentifier("reconnect-bonded")
                Text(runtime.latestEvent).font(.caption).foregroundStyle(Palette.muted)
            } else {
                PrimaryButton(title: "시뮬레이터에서는 안경에 연결할 수 없음", icon: "link", enabled: false) {}
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                Button { store.selectedTab = 1 } label: { shortcut("mic", title: "음성 도우미", subtitle: "음성 인식과 대화") }.buttonStyle(.plain)
                Button { store.selectedTab = 2 } label: { shortcut("folder", title: "녹음 보관함", subtitle: "기기에 저장된 오디오 관리") }.buttonStyle(.plain)
                NavigationLink { PrompterView() } label: { shortcut("text.alignleft", title: "프롬프터", subtitle: "편집 및 휴대폰 미리보기") }.buttonStyle(.plain)
                NavigationLink { TodoView() } label: { shortcut("checkmark.circle", title: "할 일 목록", subtitle: "할 일 기록 및 관리") }.buttonStyle(.plain)
            }
            NavigationLink { QWeatherDashboardView() } label: {
                Label(qweather.status, systemImage: "cloud.sun")
                    .font(.caption).foregroundStyle(Palette.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityIdentifier("device-weather-status")
            Button { showConnection = true } label: {
                Label("로컬 기능 사용 가능 · 안경 제어 확인 필요", systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Palette.green).padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { runtime.prepare() }
        .sheet(isPresented: $showConnection) { ConnectionBoundaryView() }
    }

    private func shortcut(_ icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(.system(size: 25, weight: .light)).foregroundStyle(Palette.ink)
                .frame(width: 34, height: 38).background(Palette.mint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }.padding(14).frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.line.opacity(0.6), lineWidth: 0.75))
    }
}

struct ConnectionBoundaryView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "link.badge.plus").font(.system(size: 35, weight: .light)).foregroundStyle(Palette.green)
                    Text("안경 연결 안내").font(.title2.bold()).foregroundStyle(Palette.ink)
                    Text("Turbo IO는 독립 앱과 저장 공간을 사용합니다. 기기용 빌드에는 안경 통신과 음성 기능이 포함됩니다. 페어링, 백그라운드 동작, 안경 표시를 실제 기기에서 확인하세요.")
                        .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                    Card {
                        FeatureRow(icon: "iphone", title: "휴대폰 로컬 기능", subtitle: "초안, 가져오기, 설정 및 상태 데모", status: "사용 가능", active: true)
                        FeatureRow(icon: "link", title: "연결, 인증 및 등록 해제", subtitle: "기기 통신 모듈 사용 · 자동 등록 해제 및 초기화 없음")
                        FeatureRow(icon: "eyeglasses", title: "안경 표시 및 기기 응답", subtitle: "각 기능을 실제 안경에서 확인하세요")
                        FeatureRow(icon: "signature", title: "일반 아이폰에 개발자 서명으로 설치", subtitle: "시뮬레이터 실행은 실제 기기 검증과 별개입니다", status: "기기 확인 필요")
                    }
                    Text("펌웨어 수정, 공식 계정 해제, 자동 마이크 실행이나 녹음 업로드를 하지 않습니다.")
                        .font(.footnote).foregroundStyle(Palette.green)
                }.padding(24)
            }.background(Palette.background).navigationTitle("연결 상태").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }
}
