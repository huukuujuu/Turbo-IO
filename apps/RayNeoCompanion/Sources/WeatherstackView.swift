import SwiftUI

struct WeatherstackView: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @EnvironmentObject private var automatic: AutomaticWeather
    @StateObject private var weather = WeatherstackController()
    @State private var city = "Beijing, China"
    @State private var key = ""
    @State private var rawIcon = ""
    @State private var acknowledgedIcon = false
    @State private var confirmQuery = false
    @State private var confirmSend = false
    @State private var lookup: Task<Void,Never>?

    var body: some View {
        Form {
            Section("연결 인증 후 자동 동기화") {
                Text("자동 날씨는 QWeather 대시보드 설정을 사용합니다. 이 화면의 조회와 재시도는 수동으로 실행합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("연결 / 재연결 후 홈 날씨 동기화", isOn: Binding(
                    get: { automatic.configuration.enabled },
                    set: { automatic.configure(city: automatic.configuration.city, enabled: $0) }))
                    .accessibilityIdentifier("weather-auto-enabled")
                Text("선택한 도시: \(automatic.configuration.city)").font(.caption)
                Text(automatic.status).font(.caption).accessibilityIdentifier("weather-auto-status")
                Text("인증 후 조회하고 전송합니다. 최근 결과는 재연결 시 재사용할 수 있습니다. 녹음·대화·프롬프터 사용 중에는 기다립니다. 별도 API 키와 확인된 아이콘 매핑이 필요합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("자동 동기화 재시도") { automatic.retry() }.disabled(automatic.busy)
                    .accessibilityIdentifier("weather-auto-retry")
                if let result = automatic.snapshot {
                    Text("자동 조회: \(result.city) \(result.lensTemperature)°C · \(result.description) · 날씨 코드 \(result.providerCode)").font(.caption)
                }
            }
            Section("Weatherstack · 실시간 날씨") {
                Text("입력한 도시만 Weatherstack에 전송하며 사용량이 발생할 수 있습니다. 휴대폰 위치, 대화, 녹음, 안경 식별 정보는 보내지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField(weather.hasKey ? "새 API 키 (비우면 기존 키 유지)" : "Weatherstack API Key",text:$key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("weather-key")
                HStack {
                    Button("API 키 안전하게 저장") { weather.saveKey(key); key = ""; automatic.retry() }.disabled(key.isEmpty || weather.busy)
                    Spacer()
                    Button("API 키 삭제",role:.destructive) { weather.removeKey(); automatic.retry() }.disabled(!weather.hasKey || weather.busy)
                }
                TextField("도시 및 국가",text:$city).autocorrectionDisabled().accessibilityIdentifier("weather-city")
                Button("자동 동기화 도시로 저장") {
                    automatic.configure(city:city, enabled:automatic.configuration.enabled)
                }.accessibilityIdentifier("weather-auto-city-save")
                Button(weather.busy ? "조회 중…" : "조회 및 미리보기 (전송 안 함)") { confirmQuery = true }
                    .disabled(weather.busy || !weather.hasKey || city.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("weather-query")
                Button("2019년 예시 데이터 보기") { weather.previewSample() }
                    .disabled(weather.busy).accessibilityIdentifier("weather-sample")
                Text(weather.message).font(.caption).accessibilityIdentifier("weather-status")
            }
            if let result = automatic.snapshot, !result.isSample {
                Section("자동 날씨 아이콘 확인") {
                    Text("Weatherstack 날씨 코드 \(result.providerCode)의 확인된 펌웨어 아이콘을 저장합니다. 확인하지 않은 새 날씨 코드는 전송하지 않습니다.")
                        .font(.caption)
                    TextField("펌웨어 아이콘 번호", text:$rawIcon).keyboardType(.numberPad)
                    Toggle("이 아이콘 매핑을 확인함", isOn:$acknowledgedIcon)
                    Button("아이콘 매핑 저장 후 재시도") {
                        guard acknowledgedIcon, let icon = validIcon else { return }
                        automatic.confirmIcon(providerCode:result.providerCode, firmwareCode:icon)
                    }.disabled(!acknowledgedIcon || validIcon == nil || automatic.busy)
                }
            }
            if let snapshot = weather.snapshot {
                Section(snapshot.isSample ? "이전 예시 · 전송 불가" : "조회 결과 · 동기화 전") {
                    LabeledContent(snapshot.city,value:String(format:"%g °C",snapshot.celsius))
                        .accessibilityIdentifier("weather-preview")
                    Text(snapshot.description)
                    Text("현지 시간: \(snapshot.sourceLocalTime.isEmpty ? "없음" : snapshot.sourceLocalTime)").font(.caption)
                    Text("Weatherstack 코드: \(snapshot.providerCode) (안경 아이콘 번호 아님)").font(.caption)
                    if snapshot.usedLegacyTemperatureKey {
                        Text("예시의 temparature 철자를 지원하지만 정식 temperature 필드를 우선합니다.").font(.caption2)
                    }
                    Text("홈에는 지역, 정수 기온, 펌웨어 아이콘만 보냅니다. 풍속, 대기질, 달의 위상 등은 전송하지 않습니다.").font(.caption)
                }
                Section("홈 날씨 동기화") {
                    TextField("검증된 펌웨어 아이콘 번호",text:$rawIcon).keyboardType(.numberPad)
                    Toggle("이 펌웨어 아이콘 번호를 확인했습니다",isOn:$acknowledgedIcon)
                    Text("제공자의 날씨 코드와 안경 아이콘은 자동 대응하지 않습니다. 기온은 정수로 반올림하며 기존 배치는 유지합니다.").font(.caption)
                    Button("조회 결과를 안경에 동기화") { confirmSend = true }
                        .disabled(!voice.ready || !snapshot.canSend(at:Date()) || !acknowledgedIcon || validIcon == nil || weather.busy)
                        .accessibilityIdentifier("weather-send")
                    Text(features.status).font(.caption)
                    if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
                }
            }
        }.navigationTitle("Weatherstack 날씨")
        .confirmationDialog("입력한 도시를 Weatherstack에서 한 번 조회할까요? 사용량이 발생할 수 있습니다.",isPresented:$confirmQuery) {
            Button("한 번 조회") { lookup = Task { await weather.refresh(city:city) } }
        }
        .confirmationDialog("미리보기의 기온과 선택한 아이콘을 안경 홈에 보낼까요?",isPresented:$confirmSend) {
            Button("동기화 확인") {
                guard let snapshot = weather.snapshot, acknowledgedIcon, let icon = validIcon else { return }
                features.sendWeatherstack(snapshot,icon:icon)
            }
        }
        .onChange(of:rawIcon) { _ in acknowledgedIcon = false }
        .onAppear { city = automatic.configuration.city }
        .onDisappear { lookup?.cancel(); key = "" }
    }
    private var validIcon: Int? { guard let n = Int(rawIcon), (0...999).contains(n) else { return nil }; return n }
}
