import SwiftUI

struct GlassesRecordingCard: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var confirmStart = false
    @State private var expanded = false
    var body: some View {
        Card {
            DisclosureGroup(isExpanded:$expanded) {
              VStack(alignment:.leading,spacing:12) {
                Text(features.recordingStatus).font(.caption).foregroundStyle(Palette.muted)
                if features.recordingBytes > 0 { Text("수신됨: \(ByteCountFormatter.string(fromByteCount:Int64(features.recordingBytes),countStyle:.file))").font(.caption.monospacedDigit()) }
                Toggle("안경에서 시작한 녹음을 이 기기에 저장 허용",isOn:Binding(get:{features.acceptsEyeRecording},set:{features.enableEyeRecording($0)}))
                    .font(.caption).disabled(features.recordingID != nil || !voice.ready)
                if features.recordingID == nil {
                    Button("안경 녹음 시작") { confirmStart = true }.disabled(!voice.ready)
                } else {
                    HStack {
                        Button("일시정지") { features.recordingControl(8) }
                        Button("복원") { features.recordingControl(9) }
                        Button("표시") { features.recordingControl(11) }
                        Button("중지") { features.recordingControl(4) }
                    }.disabled(!voice.ready)
                }
                Text("녹음 중에는 음성 대기가 일시정지됩니다. 오디오만 저장하며 자동 전사, 업로드, 안경 파일 삭제는 하지 않습니다. 종료 후 대화 화면에서 음성 대기를 다시 켜세요. 오프라인 녹음 가져오기는 별도 확인이 필요합니다.").font(.caption2).foregroundStyle(Palette.muted)
                if let file = features.completedRecording {
                    HStack { ShareLink(item:file) { Label("WAV 공유",systemImage:"square.and.arrow.up") }; Button("보관 다시 시도") { Task { await features.archiveReceivedRecording() } } }.font(.caption)
                } else if features.recordingID != nil {
                    Button("완료 메시지 수신 후 다시 검증") { features.retryRecordingFinish() }.font(.caption)
                }
                if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
              }.padding(.top,12)
            } label: {
                VStack(alignment:.leading,spacing:6) {
                    Label("안경 녹음",systemImage:"mic.badge.plus").font(.headline)
                    Text(features.recordingID == nil ? "녹음 제어 펼치기 · 기본 녹음 꺼짐" : features.recordingStatus).font(.caption2).foregroundStyle(Palette.muted)
                }
            }.accessibilityIdentifier("recording-controls").padding(18)
            NavigationLink("앱 재시작 전 수신 파일 찾기") { RecordingRecoveryView() }
                .font(.caption).padding(.horizontal,18).padding(.bottom,14).accessibilityIdentifier("recording-recovery")
        }
        .confirmationDialog("안경에서 녹음을 시작하여 Turbo IO에 저장할까요? AI 음성 대기가 일시정지되며 자동 업로드하지 않습니다.",isPresented:$confirmStart) {
            Button("녹음 시작") { features.startRecording() }
        }
        .onAppear { features.prepare() }
        .onChange(of:features.recordingID) { if $0 != nil { expanded = true } }
    }
}

struct GlassesTodoSyncCard: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var confirm = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Button("이 기기의 할 일을 안경에 동기화") { confirm = true }.disabled(!voice.ready)
            Text(features.todoStatus).font(.caption).foregroundStyle(Palette.muted)
            Text("첫 동기화에는 확인이 필요합니다. 연결된 항목은 온라인 편집 시 전송하며 오프라인 변경은 재시도를 위해 보관합니다. 충돌은 전송 대기 및 충돌 화면에서 처리하세요. 기기에서 항목을 보관해도 안경의 항목은 삭제되지 않습니다.").font(.caption2).foregroundStyle(Palette.muted)
            if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
        }
        .confirmationDialog("보관되지 않은 할 일을 현재 안경에 보낼까요? 공식 앱의 다른 할 일을 덮어쓰지 않습니다.",isPresented:$confirm) {
            Button("할 일 전송") { features.syncTodos() }
        }.onAppear { features.prepare() }
    }
}

struct GlassesPrompterControls: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    let text: String
    @State private var speed = 120.0
    @State private var confirm = false
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("안경 프롬프터 · 일정 속도").font(.headline)
            Text(features.teleprompterStatus).font(.caption).foregroundStyle(Palette.muted)
            HStack { Text("스크롤 속도"); Spacer(); Text("분당 \(Int(speed))자 (설정값)").monospacedDigit() }.font(.caption)
            Slider(value:$speed,in:60...240,step:10)
            if features.teleprompterID == nil {
                Button("현재 원고 준비 및 전송") { confirm = true }.disabled(!voice.ready || text.isEmpty)
            } else {
                HStack {
                    Button("시작") { features.teleprompterControl(3) }
                    Button("일시정지") { features.teleprompterControl(4) }
                    Button("계속") { features.teleprompterControl(5) }
                    Button("나가기") { features.teleprompterControl(6) }
                }.disabled(!voice.ready)
                Button("스크롤 속도 적용") { features.teleprompterControl(7,speed:Int(speed)) }.disabled(!voice.ready)
            }
            Text("현재 구간만 전송합니다(최대 12,000자). 수신 확인 후 시작할 수 있습니다. 안경이 보고하는 진행률은 휴대폰 페이지와 다르며 음성 추적 스크롤은 사용하지 않습니다.").font(.caption2).foregroundStyle(Palette.muted)
            if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
        }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:16))
        .confirmationDialog("현재 텍스트를 안경에 보낼까요? AI 음성 대기가 일시정지됩니다. 텍스트는 로컬 연결로만 전송합니다.",isPresented:$confirm) {
            Button("현재 원고 준비") { features.prepareTeleprompter(text,speed:Int(speed)) }
        }.onAppear { features.prepare() }
    }
}

struct GlassesSettingsView: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var location = "테스트 도시"
    @State private var temperature = 27
    @State private var icon = "100"
    @State private var description = "사용자 테스트 날씨"
    @State private var confirmWeather = false
    var body: some View {
        Form {
            Section("연결 및 실제 기기 상태") {
                Text(voice.ready ? "인증된 연결" : "연결 안 됨 (시뮬레이터는 전송하지 않음)")
                LabeledContent("배터리",value:features.battery.map { "\($0)%" } ?? "조회 전")
                LabeledContent("밝기",value:features.brightness.map(String.init) ?? "조회 전")
                Button("안경 상태 및 설정 읽기") { features.refreshSettings() }.disabled(!voice.ready)
                Text(features.status).font(.caption)
            }
            Section("날씨 서비스") {
                NavigationLink("대시보드 실시간 날씨 · QWeather") { QWeatherDashboardView() }.accessibilityIdentifier("qweather-entry")
                NavigationLink("Weatherstack 수동 조회 (이전 방식)") { WeatherstackView() }.accessibilityIdentifier("weatherstack-entry")
                Text("별도 API 키 · 수동 조회 · 미리보기 후 동기화 확인. 위치 권한은 필요하지 않습니다.").font(.caption)
            }
            Section("확인된 기기 설정") {
                HStack { Button("밝기 7") { features.setBrightness(7) }; Spacer(); Button("밝기 8") { features.setBrightness(8) } }
                HStack { Button("15초 후 절전") { features.setSleep(15) }; Spacer(); Button("25초 후 절전") { features.setSleep(25) } }
                Button("머리 동작 켜기 · 모드 0") { features.setHeadControl(true,mode:0) }
                Button("머리 동작 끄기") { features.setHeadControl(false,mode:0) }
                Button("두 번 탭하여 할 일 열기") { features.setDoubleTapTodo(true) }
                Button("두 번 탭하여 AI 열기") { features.setDoubleTapTodo(false) }
                Button("표시 높이 1") { features.setDisplay(height:1) }
                Button("표시 높이 3") { features.setDisplay(height:3) }
                Button("표시 거리 1") { features.setDisplay(distance:1) }
                Button("표시 거리 2") { features.setDisplay(distance:2) }
                Text("확인된 설정값만 사용하며 알 수 없는 개인정보 항목은 변경하지 않습니다. 전송 후 실제 안경의 동작을 확인하세요.").font(.caption)
            }.disabled(!voice.ready)
            Section("사용자 날씨 · 실시간 기상 정보 아님") {
                TextField("도시 표시 이름",text:$location)
                Stepper("기온 \(temperature)",value:$temperature,in:-80...60)
                TextField("펌웨어 아이콘 번호",text:$icon).keyboardType(.numberPad)
                TextField("날씨 설명",text:$description)
                Button("홈 화면에 테스트 날씨 전송") { confirmWeather = true }.disabled(!voice.ready || Int(icon) == nil)
                Text("내용만 전송하며 기존 대시보드 배치는 바꾸지 않습니다. 홈 날씨와 도시 카드는 별도 채널입니다. 아이콘은 안경에서 확인하세요. 이 테스트는 위치 조회나 자동 갱신을 하지 않습니다.").font(.caption)
            }
            if let error = features.error { Section("작업 안내") { Text(error).foregroundStyle(Palette.amber) } }
        }.navigationTitle("날씨 및 기기 설정")
        .confirmationDialog("이 테스트 날씨를 안경에 보낼까요?",isPresented:$confirmWeather) {
            Button("사용자 데이터 전송") { features.sendWeather(location:location,temperature:temperature,icon:Int(icon) ?? 100,description:description) }
        }.onAppear { features.prepare() }
    }
}
