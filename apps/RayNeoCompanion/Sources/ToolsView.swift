import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var showModel = false
    @State private var showLab = false
    var body: some View {
        Screen(title: "도구 모음", eyebrow: "로컬 도구 및 실험 기능") {
            NavigationLink { ExternalServicesView() } label: {
                Card { FeatureRow(icon: "questionmark.circle", title: "외부 AI·서비스 연결 안내", subtitle: "음성 인식 · 답변 AI · Codex · 설정 초안의 차이", status: "도움말", active: true) }
            }.buttonStyle(.plain).accessibilityIdentifier("external-services-guide")
            NavigationLink { DisplayObserverView() } label: {
                Card { FeatureRow(icon: "eyeglasses", title: "디스플레이 관찰", subtitle: "USB · 화면 상태와 전송 텍스트 · 스크린샷 아님", status: "읽기 전용") }
            }.buttonStyle(.plain).accessibilityIdentifier("display-observer-entry")
            NavigationLink { AlwaysOnLocalProbeView(probe: store.alwaysOn) } label: {
                Card { FeatureRow(icon: "waveform.path", title: "일상 기록", subtitle: "오디오 전용 · 30초 로컬 프로토콜 테스트", status: "실험 기능") }
            }.buttonStyle(.plain).accessibilityIdentifier("always-on-entry")
            NavigationLink { ModelToolsView() } label: {
                Card { FeatureRow(icon: "wrench.and.screwdriver", title: "AI Tools", subtitle: "모델 도구 · 매개변수 · 사용 조건", status: "보기") }
            }.buttonStyle(.plain).accessibilityIdentifier("model-tools-entry")
            NavigationLink { CodexCompanionView() } label: {
                Card { FeatureRow(icon: "terminal", title: "Codex 콘솔", subtitle: "PC 작업 · 진행 상황 · 개별 승인", status: "PC 연결") }
            }.buttonStyle(.plain).accessibilityIdentifier("codex-tool")
            Card {
                NavigationLink { TodoView() } label: {
                    FeatureRow(icon: "checklist", title: "할 일 목록", subtitle: "할 일 기록 및 관리", status: "로컬 사용 가능", active: true)
                }.buttonStyle(.plain).accessibilityIdentifier("todo-tool")
                Divider().overlay(Palette.line)
                NavigationLink { PrompterView() } label: {
                    FeatureRow(icon: "text.alignleft", title: "프롬프터", subtitle: "원고 편집 및 휴대폰 미리보기", status: "로컬 사용 가능", active: true)
                }.buttonStyle(.plain).accessibilityIdentifier("prompter-tool")
            }
            Card {
                Button { showModel = true } label: { FeatureRow(icon: "gearshape", title: "다른 모델 설정 초안", subtitle: "저장 전용 · 실제 음성 AI에는 적용되지 않음", status: "초안") }.buttonStyle(.plain)
                Divider().overlay(Palette.line)
                Button { showLab = true } label: { FeatureRow(icon: "flask", title: "프로토콜 실험실", subtitle: "프로토콜 및 기능 실험", status: "로컬 시뮬레이션") }.buttonStyle(.plain).accessibilityIdentifier("protocol-lab")
            }
            VStack(spacing: 12) {
                SectionLabel(title: "안경 기능", trailing: "실제 기기 연동 · 재확인 필요")
                Card {
                    NavigationLink { NotificationCenterView() } label: { FeatureRow(icon: "bell.badge", title: "알림 센터", subtitle: "앱별 알림 설정 및 사용자 알림 테스트", status: "실제 기기") }.buttonStyle(.plain).accessibilityIdentifier("notification-tool")
                    Divider().overlay(Palette.line)
                    NavigationLink { HeadControlNotificationTestView() } label: { FeatureRow(icon: "person.crop.circle.badge.checkmark", title: "머리 동작 알림 테스트", subtitle: "할 일 제안 카드 · 끄덕임/고개 젓기 결과를 앱에서 확인", status: "실제 기기") }.buttonStyle(.plain).accessibilityIdentifier("head-control-test-entry")
                    Divider().overlay(Palette.line)
                    NavigationLink { GlassesSettingsView() } label: { FeatureRow(icon: "cloud", title: "날씨 및 기기 설정", subtitle: "사용자 데이터 및 기기 상태 조회·설정", status: "실제 기기") }.buttonStyle(.plain).accessibilityIdentifier("device-settings-tool")
                    Divider().overlay(Palette.line)
                    NavigationLink { GlassesSettingsView() } label: { FeatureRow(icon: "slider.vertical.3", title: "머리 동작 및 다이얼", subtitle: "확인된 프로토콜 설정만 지원", status: "실제 기기") }.buttonStyle(.plain)
                }
            }
            Label("기능의 실제 동작은 안경에서 확인하세요", systemImage: "info.circle")
                .font(.system(size: 12)).foregroundStyle(Palette.green).padding(15)
                .frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 15))
            HStack {
                NavigationLink("사용 안내") { HelpView() }
                Spacer()
                NavigationLink("지원 범위") { ProtocolLabView() }
                Spacer()
                NavigationLink("설정") { SettingsView(embedded: true) }
            }.font(.system(size: 12)).padding(.horizontal, 5)
        }
        .sheet(isPresented: $showModel) { ModelConfigurationView() }
        .sheet(isPresented: $showLab) { SessionSimulationView() }
    }

    private func toolTile(_ icon: String, title: String, description: String, footnote: String, green: Bool) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Image(systemName: icon).font(.system(size: 25, weight: .light)); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(description).font(.system(size: 11)).opacity(0.7)
            }
            Text(footnote).font(.system(size: 10)).opacity(0.7)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 160)
            .foregroundStyle(green ? Palette.mint : Palette.ink)
            .background(green ? Palette.ink : Palette.mint.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ModelToolsView: View {
    @EnvironmentObject private var codex: CodexCompanion
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @State private var refreshing = false
    @State private var expandedTools: Set<String> = []
    private var providedNames: Set<String> {
        Set(codex.toolDefinitions.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    Label("DeepSeek 도구 목록", systemImage: "wrench.and.screwdriver").font(.headline)
                    Text("제공할 도구: \(providedNames.count) / \(CodexToolDescriptor.all.count)개")
                        .accessibilityIdentifier("model-tools-count")
                    Text("다음 모델 요청에 포함할 수 있는 도구입니다. 호출이나 실행 성공, PC 연결 상태를 뜻하지 않습니다. 이 화면은 읽기 전용이며 작업을 시작하지 않습니다.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text(codex.configured ? (codex.voiceToolsEnabled ? "도구 권한: 허용됨" : "도구 권한: 꺼짐") : "도구 설정: 브리지 주소 또는 토큰 필요")
                        .font(.caption).accessibilityIdentifier("model-tools-configuration")
                    Text(runtime.supportsDevice ? "음성: \(runtime.phaseLabel) · \(runtime.cloud ? "클라우드 대화" : "클라우드 대화 꺼짐")" : "시뮬레이터: 목록만 표시하며 안경 음성을 실행하지 않습니다")
                        .font(.caption)
                    Text("브리지 상태 (최근 확인 / 설정 결과): \(codex.status)").font(.caption)
                        .accessibilityIdentifier("model-tools-bridge-state")
                    Button(refreshing ? "확인 중…" : "브리지 연결 확인 (작업 전송 없음)") {
                        refreshing = true
                        Task { await codex.refresh(); refreshing = false }
                    }.disabled(!codex.configured || refreshing).accessibilityIdentifier("model-tools-refresh")
                    NavigationLink("Codex 도구 허용 및 연결 관리") { CodexCompanionView() }
                        .accessibilityIdentifier("model-tools-configure")
                }
                ForEach(CodexToolDescriptor.all) { tool in
                    Card {
                        Text(tool.title).font(.headline)
                        Text(tool.id).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
                            .accessibilityIdentifier("model-tool-name-\(tool.id)")
                        Badge(text: providedNames.contains(tool.id) ? "모델 요청에 포함됨" : "모델에 제공하지 않음")
                        Text(tool.description).font(.subheadline)
                        Text(tool.requiresText ? "매개변수: text (필수 문자열, 작업 요청)" : "매개변수: 없음, 현재 선택한 작업 사용")
                            .font(.caption).foregroundStyle(Palette.muted)
                        Text("이렇게 말해 보세요: “\(tool.example)”").font(.caption).foregroundStyle(Palette.green)
                        Button {
                            if expandedTools.contains(tool.id) { expandedTools.remove(tool.id) }
                            else { expandedTools.insert(tool.id) }
                        } label: {
                            HStack {
                                Text(expandedTools.contains(tool.id) ? "도구 정의 접기 (JSON)" : "실제 도구 정의 보기 (JSON)")
                                Spacer()
                                Image(systemName: expandedTools.contains(tool.id) ? "chevron.down" : "chevron.right")
                            }.frame(minHeight: 44)
                        }.accessibilityIdentifier("model-tool-details-\(tool.id)")
                            .accessibilityValue(expandedTools.contains(tool.id) ? "펼쳐짐" : "접힘")
                        if expandedTools.contains(tool.id) {
                            Text(tool.schemaJSON).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("model-tool-schema-\(tool.id)")
                        }
                    }
                }
                Text("현재 Function Calling을 사용합니다. 할 일, 날씨, 녹음 기능은 아직 모델 도구에 등록되지 않았습니다. 권한 승인은 휴대폰에서 직접 확인해야 하며 자동 승인 도구는 없습니다.")
                    .font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("model-tools-boundary")
            }.padding(22)
        }.background(Palette.background).navigationTitle("AI Tools").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}

struct TodoView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var title = ""
    @State private var showCompleted = false
    @State private var editingTodo: LocalTodo?
    @FocusState private var inputFocused: Bool
    private var visibleTodos: [LocalTodo] { store.todos.filter { $0.archivedAt == nil && $0.completed == showCompleted } }
    private var markdown: String {
        "# Turbo IO 할 일 목록\n\n> 이 기기의 현재 기록이며 안경 동기화나 표시 확인을 의미하지 않습니다.\n\n" + store.todos.filter { $0.archivedAt == nil }.map {
            "- [\($0.completed ? "x" : " ")] \($0.title.replacingOccurrences(of: "\n", with: " "))"
        }.joined(separator: "\n")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                notice("먼저 기기에 저장 · 안경 동기화 시 확인 필요")
                NavigationLink("시스템 미리 알림에서 가져오기") { ReminderImportView() }
                    .accessibilityIdentifier("system-reminders-open")
                Picker("할 일 필터", selection: $showCompleted) {
                    Text("진행 중").tag(false); Text("완료됨").tag(true)
                }.pickerStyle(.segmented)
                HStack(spacing: 12) {
                    TextField("할 일 추가…", text: $title, axis: .vertical).lineLimit(1...3).accessibilityIdentifier("todo-input").focused($inputFocused)
                    Button {
                        store.addTodo(title); title = ""
                        inputFocused = false
                        showCompleted = false
                    } label: { Image(systemName: "plus").font(.system(size: 17, weight: .medium)).foregroundStyle(.white).frame(width: 36, height: 36).background(Palette.ink, in: Circle()) }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("기기에 저장")
                }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 0.75))
                if visibleTodos.isEmpty {
                    Card { EmptyState(icon: "checkmark.circle", title: showCompleted ? "완료한 할 일이 없습니다" : "진행 중인 할 일이 없습니다", detail: "작은 할 일부터 시작해 보세요.\n공식 앱의 할 일을 표시하거나 수정하지 않습니다.") }
                } else {
                    ForEach(visibleTodos) { todo in
                        Button { store.toggleTodo(todo.id) } label: {
                            Card {
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle").font(.system(size: 23)).foregroundStyle(Palette.green)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(todo.title).font(.system(size: 15)).strikethrough(todo.completed).foregroundStyle(todo.completed ? Palette.muted : Palette.ink)
                                        Text(todo.deliveryDescription).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                        if let day = SystemReminderSnapshot.dateOnlyLabel(todo.reminderDueComponents) {
                                            Text("예정: " + day).font(.caption2).foregroundStyle(Palette.muted)
                                        } else if let due = todo.dueAt { Text("예정: " + due.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Palette.muted) }
                                        if todo.reminderSourceID != nil { Text("시스템 미리 알림에서 가져온 사본 · 원본 수정 없음").font(.caption2).foregroundStyle(Palette.muted) }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }.buttonStyle(.plain).accessibilityLabel("\(todo.title)，\(todo.completed ? "이 기기에서 완료" : "이 기기에서 미완료")")
                            .contextMenu {
                                Button("내용 및 예정 시간 편집") { editingTodo = todo }
                                Button("보관된 할 일로 이동", role: .destructive) { store.archiveTodo(todo.id, archived: true) }
                            }
                    }
                }
                HStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.green)
                    VStack(alignment: .leading, spacing: 7) {
                        GlassesTodoSyncCard()
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
                ShareLink(item: markdown) {
                    Label("할 일 목록 내보내기", systemImage: "arrow.down.to.line")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(17)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14))
                }.disabled(store.todos.isEmpty)
                Text("이 기기의 Markdown 텍스트만 공유하며 안경으로 보내지 않습니다.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                NavigationLink("보관된 할 일 (복원 가능)") { RemovedTodosView() }
                NavigationLink("전송 대기 및 충돌") { TodoDeliveryView() }
                    .accessibilityIdentifier("todo-delivery-open")
                Text("길게 누르면 편집하거나 보관할 수 있습니다. 예정 시간은 기록용이며 시스템 알림을 만들지 않습니다.").font(.caption).foregroundStyle(Palette.muted)
            }.padding(24)
        }.background(Palette.background).navigationTitle("할 일 목록").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .sheet(item: $editingTodo) { TodoEditorView(todo: $0) }
    }
}

struct TodoEditorView: View {
    let todo: LocalTodo
    @EnvironmentObject private var store: CompanionStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDate = false
    @State private var due = Date()
    var body: some View {
        NavigationStack {
            Form {
                TextField("할 일 내용", text: $title, axis: .vertical).accessibilityIdentifier("todo-edit-title")
                Toggle("예정 시간 (자동 알림 없음)", isOn: $hasDate)
                if hasDate { DatePicker("시간", selection: $due) }
                Text("안경과 연결된 항목은 온라인 상태에서 내용과 완료 상태 동기화를 시도합니다. 예정 시간은 기기에만 저장하며 알림을 생성하지 않습니다.").font(.caption)
            }.navigationTitle("할 일 편집").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("저장") {
                    store.editTodo(todo.id, title: title, dueAt: hasDate ? due : nil); dismiss()
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.onAppear { title = todo.title; hasDate = todo.dueAt != nil; due = todo.dueAt ?? Date() }
        }
    }
}

struct RemovedTodosView: View {
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        List {
            ForEach(store.todos.filter { $0.archivedAt != nil }) { todo in
                HStack { Text(todo.title); Spacer(); Button("복원") { store.archiveTodo(todo.id, archived: false) } }
            }
        }.navigationTitle("보관된 할 일").toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}

struct PrompterView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var text = ""
    @State private var fontSize = 22.0
    @State private var mode = "编辑"
    @State private var page = 0
    @State private var saved = false
    private var pages: [String] { LocalPrompterPager.pages(text) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("프롬프터 모드", selection: $mode) { Text("편집").tag("编辑"); Text("휴대폰 미리보기").tag("手机预览") }.pickerStyle(.segmented)
                NavigationLink { BookShelfView() } label: {
                    Card { FeatureRow(icon: "books.vertical", title: "책 가져오기 및 자동 읽기", subtitle: "TXT / EPUB · 장 · 재생 속도 · 이어 읽기", status: "로컬 사용 가능", active: true) }
                }.buttonStyle(.plain).accessibilityIdentifier("book-shelf")
                if mode == "编辑" {
                    Card {
                        HStack { Text("내 원고").font(.headline).foregroundStyle(Palette.ink); Spacer(); Text("\(text.count)자").font(.caption).foregroundStyle(Palette.muted) }
                        ZStack(alignment: .topLeading) {
                            if text.isEmpty { Text("말하고 싶은 내용을 입력하세요…").foregroundStyle(Palette.muted).padding(.top, 8).padding(.leading, 5) }
                            TextEditor(text: $text).scrollContentBackground(.hidden).frame(minHeight: 260).accessibilityIdentifier("prompter-input")
                        }.font(.system(size: 16)).padding(10).background(Palette.background, in: RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Text("휴대폰 레이아웃 미리보기").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                    VStack {
                        ScrollView {
                            Text(pages.isEmpty ? "원고가 없습니다. 편집 화면에서 내용을 입력하세요." : pages[min(page, pages.count - 1)])
                                .font(.system(size: fontSize, weight: .medium)).foregroundStyle(Palette.mint).lineSpacing(14)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        }.frame(height: 210)
                        Text(pages.isEmpty ? "내용 없음" : "휴대폰 페이지 \(page + 1) / \(pages.count)").font(.system(size: 11)).foregroundStyle(Palette.mint.opacity(0.6)).padding(.bottom, 16)
                    }.background(Palette.ink, in: RoundedRectangle(cornerRadius: 20))
                    HStack { Text("글자 크기"); Spacer(); Text("\(Int(fontSize))").monospacedDigit() }.font(.subheadline)
                    HStack { Text("A").font(.caption); Slider(value: $fontSize, in: 16...40, step: 1); Text("A").font(.title3) }
                    HStack {
                        Button { page = max(0, page - 1) } label: { Label("이전 페이지", systemImage: "chevron.left").frame(maxWidth: .infinity) }.disabled(page == 0)
                        Button { page = min(pages.count - 1, page + 1) } label: { Label("다음 페이지", systemImage: "chevron.right").frame(maxWidth: .infinity) }.disabled(page + 1 >= pages.count)
                    }.font(.system(size: 13)).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    Text("휴대폰 읽기를 위해 140자 단위로 나눕니다. 안경의 페이지 구분과는 다릅니다.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                HStack(spacing: 12) {
                    Button { store.savePrompter(text); saved = true } label: {
                        Label(saved ? "저장됨" : "초안 저장", systemImage: saved ? "checkmark" : "square.and.arrow.down").frame(maxWidth: .infinity)
                    }.accessibilityIdentifier("prompter-save")
                    ShareLink(item: text) { Label("원고 공유", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.disabled(text.isEmpty)
                }.font(.system(size: 13, weight: .medium)).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.green, lineWidth: 0.75))
                GlassesPrompterControls(text:text)
                notice("안경 레이아웃과 다이얼 조작은 실제 기기에서 확인하세요")
            }.padding(24)
        }.background(Palette.background).navigationTitle("프롬프터").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .onAppear { text = store.prompterText }.onChange(of: text) { _ in saved = false; page = 0 }
    }
}

enum LocalPrompterPager {
    static func pages(_ text: String, charactersPerPage: Int = 140) -> [String] {
        guard !text.isEmpty, charactersPerPage > 0 else { return [] }
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: charactersPerPage, limitedBy: text.endIndex) ?? text.endIndex
            result.append(String(text[start..<end]))
            start = end
        }
        return result
    }
}

private func notice(_ text: String) -> some View {
    Label { Text(text).lineSpacing(4) } icon: { Image(systemName: "info.circle") }
        .font(.system(size: 12)).foregroundStyle(Palette.green).padding(14)
        .frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
}

struct ProtocolLabView: View {
    private let capabilities: [(String, String, String)] = [
        ("연결 및 인증", "휴대폰 → 안경 / 안경 → 휴대폰", "기기용 빌드는 통신 모듈을 사용합니다. 새 앱의 페어링, 백그라운드 동작 및 등록 해제는 기기에서 확인해야 합니다. 시뮬레이터는 통신 모듈을 사용하지 않습니다."),
        ("음성 처리", "호출, 오디오, 인식, 응답, 종료", "클라우드 ASR/VAD, Flash 스트리밍, 연속 끼어들기를 지원합니다. API 키 설정 후 직접 켜세요. 새 앱의 안경 표시는 기기 확인이 필요합니다."),
        ("안경의 할 일 상태 응답", "안경에서 완료 → 휴대폰에 반영", "휴대폰 체크만으로 안경 응답을 확인할 수 없습니다. ID, 수정 시간 및 중복 이벤트 방지가 필요합니다."),
        ("프롬프터 및 표시", "휴대폰 전송 / 안경 다이얼 및 페이지 조작", "페이지, 레이아웃, 머리 동작 및 종료를 실제 안경에서 확인하세요. 휴대폰 미리보기와는 별개입니다."),
        ("녹음 및 오프라인 동기화", "안경 파일 → 휴대폰 보관함", "온라인 제어, offset 기반 수신, Ogg/WAV 및 보관을 지원합니다. 오프라인 가져오기, 재시작 후 자동 이어받기는 추가 확인이 필요합니다."),
        ("날씨 및 알림", "휴대폰 내용 → 안경 표시", "전송 성공과 안경 표시를 별도로 확인합니다. 시스템 알림 공유와 사용자 알림은 별개입니다.")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                notice("기능의 연동 범위를 설명하는 화면입니다. 실험 명령을 보내거나 공식 앱을 읽지 않습니다.")
                ForEach(capabilities, id: \.0) { item in
                    Card {
                        HStack { Text(item.0).font(.headline).foregroundStyle(Palette.ink); Spacer(); Badge(text: "연동 / 확인 필요") }
                        Text(item.1).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Palette.green)
                        Text(item.2).font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(5)
                    }
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle("프로토콜 실험실").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: CompanionStore
    @Environment(\.dismiss) private var dismiss
    var embedded = false
    var body: some View {
        if embedded { settingsContent } else {
            NavigationStack { settingsContent.toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } } }
        }
    }
    private var settingsContent: some View {
        Form {
            Section {
                Toggle("화면 데모 사용", isOn: $store.demoMode).disabled(store.voice.supportsDevice)
                Text("이번 실행에만 적용됩니다. 데모는 오디오 생성, 모델 호출 또는 실제 기기 상태 변경을 하지 않습니다.")
                    .font(.footnote).foregroundStyle(Palette.muted)
            } header: { Text("데모 모드") }
            Section("개인정보 및 보안") {
                Label("마이크를 자동으로 켜지 않음", systemImage: "mic.slash")
                Label("오디오와 초안을 자동으로 업로드하지 않음", systemImage: "network.slash")
                Label("모델 API 키는 시스템 키체인에만 저장", systemImage: "key")
                Label("공식 앱 계정 및 기기 등록을 변경하지 않음", systemImage: "lock.shield")
            }.font(.subheadline)
            Section("현재 빌드") {
                LabeledContent("버전", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0") + " · 연구용 한국어 빌드")
                LabeledContent("기기 통신", value: store.voice.supportsDevice ? "제조사 통신 모듈 · 기기 재확인 필요" : "시뮬레이터에서 비활성화")
                LabeledContent("최소 OS", value: "iOS 16")
                Text("컴파일 및 시뮬레이터 실행만으로 실제 기기 연결이나 안경 표시가 검증되지는 않습니다.")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
        }.navigationTitle("설정").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: embedded)
    }
}

struct HelpView: View {
    private let sections: [(String, String)] = [
        ("어떤 기능을 사용할 수 있나요?", "로컬 할 일, 프롬프터 원고, 오디오 사본 가져오기 및 검증, 직접 입력한 텍스트의 Markdown 수정본과 공유, 모델 설정 초안 및 키체인 저장을 사용할 수 있습니다."),
        ("어떤 기능에 추가 검증이 필요한가요?", "Bluetooth 연결, 독립 인증, 음성 수집·인식, 모델 호출, TTS, 안경 표시, 안경 응답 및 NAS 자동 보관은 실제 기기와 서비스에서 확인해야 합니다. 검증되지 않은 기능을 성공으로 표시하지 않습니다."),
        ("녹음은 어디에 저장되나요?", "새 보관 파일은 Turbo IO 앱의 Documents/VerifiedRecordingArchiveV1에 저장합니다. 이전 ImportedRecordings는 유지하며 확인한 항목만 복사합니다. 원본 수정, 자동 재생·인식·업로드는 하지 않습니다."),
        ("데모가 안경을 변경하나요?", "아니요. 데모는 휴대폰 화면과 로직 테스트입니다. 상단에 데모 표시가 나오며 재실행 시 실제 연결 상태로 돌아갑니다."),
        ("나의 AI 서비스를 어떻게 연결하나요?", "음성 대화는 Alibaba Cloud ASR와 DeepSeek Flash를 사용합니다. 음성 서비스 API 키 화면에서 설정한 뒤 대기를 켜세요. 다른 모델 설정 초안은 실제 음성 서비스를 바꾸지 않습니다."),
        ("초기화나 업데이트 버튼이 없는 이유는?", "연구용 빌드입니다. 프로토콜, 복구 방법, 대상 기기가 검증된 기능만 확인 절차와 함께 제공합니다."),
        ("정상 동작은 어떻게 확인하나요?", "코드 테스트, 앱 실행, 실제 안경 표시 및 안경의 조작 응답을 각각 확인하세요. 본인 서명으로 설치한 일반 아이폰에서 전체 흐름을 검증해야 합니다.")
    ]
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(sections, id: \.0) { item in
                    Card {
                        Text(item.0).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                        Text(item.1).font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(5)
                    }
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle("사용 안내").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}
