import SwiftUI

struct ExternalServiceGuide: Identifiable {
    let id: String
    let title: String
    let state: String
    let purpose: String
    let setup: String
    let data: String
    static let all: [Self] = [
        .init(id: "asr", title: "1. 음성 인식 · Alibaba Cloud ASR", state: "음성 대화에 필요",
              purpose: "안경 마이크의 소리를 글로 바꿉니다. 질문에 답하는 AI와는 별도 서비스입니다.",
              setup: "음성 AI 연결 설정에서 본인의 ASR 호스트명과 Alibaba Cloud API 키를 입력합니다. 이 빌드는 *.aliyuncs.com 호스트와 qwen-audio-3.0-asr-flash-streaming 모델의 DashScope 스트리밍 프로토콜을 사용합니다. 해당 서비스·지역의 지원 여부는 따로 확인해야 합니다.",
              data: "음성 대기를 켠 뒤 안경에서 호출하면 오디오를 설정한 ASR 서비스로 전송합니다. 녹음 파일의 수동 전사도 이 ASR 키를 사용하며 별도 사용료가 발생할 수 있습니다."),
        .init(id: "llm", title: "2. 답변 생성 · DeepSeek", state: "음성 대화에 필요",
              purpose: "ASR로 인식한 질문을 받아 답변을 만듭니다. 응답 텍스트를 안경에 표시합니다.",
              setup: "같은 음성 AI 연결 설정 화면에 DeepSeek API 키를 넣습니다. 현재 실행기는 공식 api.deepseek.com의 deepseek-v4-flash 모델로 고정되어 있습니다. 다른 모델 설정 초안의 주소나 이름을 바꿔도 이 실행기는 바뀌지 않습니다.",
              data: "인식한 텍스트와 대화 문맥이 DeepSeek로 전송됩니다. ASR와 별도 서비스이므로 각각의 키와 사용량이 필요합니다. 이 V1 음성 경로에는 답변 읽어주기(TTS)가 연결되어 있지 않습니다."),
        .init(id: "recording", title: "3. 녹음 → 텍스트", state: "선택 기능 · ASR 키만 필요",
              purpose: "저장한 녹음을 사용자가 선택해 전사하고 새 Markdown 수정본으로 저장합니다. 녹음을 받는 것만으로 자동 전사하지 않습니다.",
              setup: "음성 AI 연결 설정에서 ASR 호스트와 키를 저장한 뒤 녹음 상세의 ASR 전사 시작을 사용합니다. 현재 키 저장 화면은 DeepSeek 키도 함께 요구하므로 ASR만 단독 구성하는 UI는 아직 제공하지 않습니다.",
              data: "전사 시작을 확인한 파일의 오디오만 ASR로 전송합니다. 전사 자체는 DeepSeek나 Codex를 사용하지 않으며 자동 요약도 하지 않습니다. 현재 파일 전사는 최대 10분 / 디코딩된 PCM 32 MiB입니다."),
        .init(id: "codex", title: "4. PC 작업 · Codex 브리지", state: "선택 기능 · 별도 PC 서비스",
              purpose: "PC에 작업을 보내거나 진행 상황과 결과를 조회합니다. 휴대폰 앱 자체가 PC의 파일을 직접 편집하는 방식은 아닙니다.",
              setup: "Mac에서 codex-bridge를 실행하고 휴대폰에서 접근 가능한 HTTPS 주소와 브리지 전용 토큰을 Codex 화면에 저장합니다. PC의 Codex 로그인과 네트워크 설정이 별도로 필요합니다. ASR나 DeepSeek API 키를 토큰 칸에 넣으면 안 됩니다.",
              data: "수동 텍스트 작업은 ASR와 DeepSeek 없이 사용할 수 있습니다. 음성으로 Codex를 부르려면 음성 대화 설정과 DeepSeek의 Codex 도구 호출 허용이 추가로 필요합니다. 브리지에는 작업 텍스트가 전달되며 승인 요청은 휴대폰에서 직접 확인합니다."),
        .init(id: "draft", title: "5. 다른 모델 설정 초안", state: "저장 전용 · 실제 연동 안 됨",
              purpose: "HTTPS 주소, 모델 이름, API 키를 저장하는 초안 화면입니다. 현재 V1의 실제 대화 실행 경로에는 연결되어 있지 않습니다.",
              setup: "여기에 다른 AI 서비스 주소나 키를 저장해도 음성 대화가 해당 서비스로 바뀌지 않습니다. 로컬 Sherpa, 사용자 클라우드, 시스템 음성, 사용자 TTS 옵션도 이 화면에서는 계획용 설정입니다.",
              data: "저장 버튼은 모델 요청을 보내지 않습니다. 키는 주소별 키체인에 저장합니다. 실제 음성 AI를 쓰려면 별도의 음성 AI 연결 설정을 사용하세요."),
        .init(id: "weather", title: "6. 날씨 · QWeather / Weatherstack", state: "선택 기능 · 날씨 전용 키",
              purpose: "날씨 API에서 받은 기온과 아이콘을 안경에 표시합니다. 생성형 AI가 날씨를 추측하는 기능이 아닙니다.",
              setup: "QWeather 대시보드는 전용 호스트, 키, 좌표가 필요합니다. 이전 Weatherstack 화면은 별도 키와 도시를 사용합니다. 자동 갱신 경로는 QWeather이며 두 서비스의 키는 서로 재사용하지 않습니다.",
              data: "입력한 좌표나 도시를 해당 날씨 서비스로 보냅니다. 휴대폰 GPS, 대화, 녹음을 보내지 않습니다. 실제 표시에는 안경 연결과 아이콘 확인이 필요합니다."),
        .init(id: "local", title: "7. 할 일 · 책 · 프롬프터 · 알림", state: "기본 기능에 AI 키 불필요",
              purpose: "할 일 편집, TXT/EPUB 읽기, 원고 작성, 오디오 보관, 사용자 알림 테스트는 로컬 기능입니다.",
              setup: "휴대폰 내 편집에는 외부 AI 계정이 필요하지 않습니다. 안경으로 보내려면 안경 연결과 기능별 확인만 필요합니다. 시스템 알림 공유 권한은 iPhone 설정에서 별도로 허용합니다.",
              data: "일반 로컬 작업은 외부 AI로 보내지 않습니다. 녹음 전사, 음성 대화 또는 PC 작업처럼 별도로 켠 기능에만 해당 서비스가 사용됩니다."),
        .init(id: "test", title: "8. 클라우드 끈 음성 테스트 · 일상 기록 실험", state: "테스트용 · AI 답변 아님",
              purpose: "로컬 음성 감지 테스트는 말소리 유무를 감지하고 무작위 테스트 문자를 보냅니다. 말을 이해하거나 질문에 답하지 않습니다. 일상 기록은 30초 프로토콜 실험입니다.",
              setup: "음성 대화의 클라우드 AI 대화를 끄면 로컬 테스트를 선택할 수 있습니다. 일상 기록 테스트는 별도의 저장 동의 후 실행합니다.",
              data: "로컬 테스트는 클라우드에 음성을 보내지 않습니다. 일상 기록 실험은 오디오를 기기에 저장하며 AI 요약·일정 추출·상시 기록 제품 기능까지 완성된 것은 아닙니다.")
    ]
}

struct ExternalServicesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    Text("음성 인식, 답변 AI, PC 작업은 서로 다른 연결입니다.").font(.headline)
                    Text("안경 마이크\n↓ 오디오\nAlibaba Cloud ASR · 말을 글로\n↓ 인식한 텍스트\nDeepSeek · 답변 생성\n↓ 응답 텍스트\n안경 화면")
                        .font(.body).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                    Text("현재 설치한 Turbo IO V1 기준입니다. 공식 앱 확장 V2의 기능 설명과 다를 수 있습니다.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                ForEach(ExternalServiceGuide.all) { item in
                    Card {
                        Text(item.title).font(.headline)
                        Badge(text: item.state)
                        Text(item.purpose)
                        Text("설정 방법").font(.subheadline.bold())
                        Text(item.setup).font(.subheadline)
                        Text("전송 데이터와 사용 범위").font(.subheadline.bold())
                        Text(item.data).font(.subheadline).foregroundStyle(Palette.muted)
                    }.accessibilityIdentifier("service-guide-\(item.id)")
                }
                Text("키는 각 공급자의 본인 계정에서 발급받아 앱에 직접 입력하세요. 설정 저장, 실제 서비스 연결, 안경 표시 성공은 각각 별도로 확인해야 합니다. 이 안내를 여는 것만으로 외부 서비스에 연결하지 않습니다.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(20)
        }.background(Palette.background)
            .navigationTitle("외부 AI·서비스 연결 안내")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}
