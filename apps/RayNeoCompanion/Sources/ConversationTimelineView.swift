import SwiftUI

struct ConversationTimelineView: View {
    @EnvironmentObject private var timeline: ConversationTimeline
    @State private var exportURL: URL?
    @State private var error: String?
    @State private var exporting = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("Turbo IO의 실제 AI 대화만 시간과 함께 기록합니다. 다른 앱의 대화나 동작 데모는 기록하지 않습니다.")
                    .font(.caption).foregroundStyle(Palette.muted)
                if let error = timeline.storageError { Text(error).font(.caption).foregroundStyle(Palette.amber) }
                PrimaryButton(title: exporting ? "내보내기 준비 중…" : "전체 대화 기록 내보내기", icon: "square.and.arrow.up", enabled: !timeline.turns.isEmpty && !exporting) {
                    exporting = true
                    Task { defer { exporting = false }; do { exportURL = try await timeline.export() } catch { self.error = "내보내지 못했습니다. 기존 기록은 삭제되지 않았습니다." } }
                }.accessibilityIdentifier("timeline-export")
                if let exportURL {
                    ShareLink(item: exportURL) { Label("공유 / 파일에 저장 (Markdown)", systemImage: "doc") }
                    Text("내보내기 시점의 기록입니다. 새 대화는 다시 내보내세요. 공유 기능으로 파일, NAS 또는 Obsidian에 저장할 수 있습니다.")
                        .font(.caption2).foregroundStyle(Palette.muted)
                }
                if timeline.turns.isEmpty {
                    Card { EmptyState(icon: "clock", title: "대화 기록이 없습니다", detail: "실제 대화는 시간순으로 기기에 저장됩니다.\n대화 화면을 닫아도 기록은 유지됩니다.") }
                }
                ForEach(timeline.turns.reversed()) { turn in
                    Card {
                        HStack { Text(turn.startedAt.formatted(date: .abbreviated, time: .standard)).font(.caption); Spacer(); Badge(text: turn.outcome) }
                        Label("나", systemImage: "person").font(.caption.bold()).foregroundStyle(Palette.green)
                        Text(turn.question.isEmpty ? "인식된 텍스트가 없습니다" : turn.question).font(.subheadline).textSelection(.enabled)
                        Divider().overlay(Palette.line)
                        Label("AI", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(Palette.green)
                        Text(turn.answer.isEmpty ? "생성된 응답이 없습니다" : turn.answer).font(.subheadline).textSelection(.enabled)
                    }.privacySensitive()
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle("대화 기록").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .alert("내보내기", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("확인") {} } message: { Text(error ?? "") }
    }
}
