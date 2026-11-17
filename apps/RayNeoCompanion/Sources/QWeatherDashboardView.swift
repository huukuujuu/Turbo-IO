import SwiftUI

struct QWeatherDashboardView: View {
    @EnvironmentObject private var weather: QWeatherDashboard
    @State private var draft = QWeatherConfiguration()
    @State private var key = ""
    @State private var test = false
    @State private var confirmIcon = false
    var body: some View {
        Form {
            Section("대시보드 홈 · 실시간 날씨") {
                Text("홈의 작은 날씨 표시를 갱신합니다. 도시별 날씨 카드나 대시보드 배치는 바꾸지 않습니다.")
                    .font(.caption)
                Text(weather.status).accessibilityIdentifier("qweather-status")
                Text(weather.reply).font(.caption).accessibilityIdentifier("qweather-reply")
            }
            Section("QWeather · 설정은 기기에 저장") {
                TextField("전용 API 호스트 (https:// 제외)",text:$draft.host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("qweather-host")
                SecureField("API 키 (비우면 이 호스트의 기존 키 유지)",text:$key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("qweather-key")
                TextField("지역 이름",text:$draft.location).accessibilityIdentifier("qweather-location")
                HStack {
                    TextField("위도",text:$draft.latitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("qweather-latitude")
                    TextField("경도",text:$draft.longitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("qweather-longitude")
                }
                Toggle("연결 인증 후 대시보드 자동 갱신",isOn:$draft.enabled).accessibilityIdentifier("qweather-enabled")
                Button("저장 및 적용") {
                    draft.host = draft.host.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
                    weather.save(draft,key:key.trimmingCharacters(in:.whitespacesAndNewlines)); key = ""
                }.disabled(weather.busy).accessibilityIdentifier("qweather-save")
                Text("저장 후 연결된 상태에서 입력한 좌표를 조회하며 사용량이 발생할 수 있습니다. 휴대폰 위치는 조회하지 않습니다. 키는 호스트별로 키체인에 저장하며 녹음이나 대화는 전송하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("조회 및 전송") {
                Button("다시 조회 / 홈 전송 재시도") { weather.retry() }.disabled(weather.busy).accessibilityIdentifier("qweather-refresh")
                if let s = weather.snapshot {
                    Text("\(weather.configuration.location) · \(s.condition) · \(String(format:"%.2f",s.temperature))°C → 안경 \(s.lensTemperature)°C")
                        .accessibilityIdentifier("qweather-preview")
                    Text("조회: \(s.fetchedAt.formatted(date:.omitted,time:.standard)) · 캐시는 최대 10분간 유지합니다. 조회 시간과 관측 시간은 다를 수 있습니다.")
                        .font(.caption)
                    Text("출처: QWeather").font(.caption)
                    ForEach(s.attributions,id:\.self) { Text($0).font(.caption2).textSelection(.enabled) }
                    Text("날씨 코드 \(s.code)는 펌웨어 아이콘과 자동 대응하지 않습니다. 테스트를 보내 안경에서 확인한 뒤 자동 전송을 켜세요.")
                        .font(.caption)
                    Button("대시보드 아이콘 테스트 전송") { test = true }.disabled(weather.busy).accessibilityIdentifier("qweather-test-dashboard")
                    Button("안경 아이콘 확인 완료 · 매핑 저장") { confirmIcon = true }.disabled(weather.busy).accessibilityIdentifier("qweather-confirm-icon")
                }
            }
        }
        .navigationTitle("대시보드 날씨")
        .preference(key:CompanionTabBarHiddenPreference.self,value:true)
        .onAppear { draft = weather.configuration }
        .onDisappear { key = "" }
        .confirmationDialog("실제 기온과 확인할 아이콘을 대시보드 홈으로 보낼까요? 날씨 카드는 변경하지 않습니다.",isPresented:$test) {
            Button("홈 테스트 한 번 전송") { weather.testCandidate() }
        }
        .confirmationDialog("안경 홈에서 기온과 올바른 아이콘을 직접 확인한 뒤 승인하세요. 프로토콜 응답만으로는 충분하지 않습니다.",isPresented:$confirmIcon) {
            Button("아이콘이 올바른 것을 직접 확인함") { weather.confirmDisplayedIcon(); draft = weather.configuration }
        }
    }
}
