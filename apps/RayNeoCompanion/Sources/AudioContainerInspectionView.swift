import SwiftUI
import RayNeoArchive
import RayNeoAudioContainer

struct AudioContainerInspectionView: View {
    @EnvironmentObject private var archive: LocalArchiveController
    @EnvironmentObject private var inspection: AudioContainerInspectionController
    let recordingID: UUID
    private var recording: ArchivedRecording? { archive.recordings.first { $0.id == recordingID } }
    private var issue: String? { archive.verificationIssues[recordingID] }
    private var ownResult: AudioContainerCheckResult? { inspection.result?.identity.recordingID == recordingID ? inspection.result : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("로컬 구조 검사", systemImage: "waveform.path.ecg").font(.caption).foregroundStyle(Palette.mint)
                    Text("구조 검사 통과와 오디오 재생 가능 여부는 별개입니다.").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text("지원 범위의 Ogg / Opus 구조만 검사합니다. 재생, 디코딩 또는 음성 인식은 하지 않습니다.")
                        .font(.caption).foregroundStyle(Palette.mint.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.ink, in: RoundedRectangle(cornerRadius: 20))
                if let recording {
                    Card {
                        Text(recording.title).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                        Text("파일 \(ByteCountFormatter.string(fromByteCount: recording.byteCount, countStyle: .file)) · 검사 한도 64 MiB")
                            .font(.caption).foregroundStyle(Palette.muted)
                        Text("보관 기록 SHA-256\n\(recording.sha256)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                    }
                    if let issue {
                        Label("보관 파일 검증 오류입니다. 상세 화면에서 전체 검증을 먼저 실행하세요.\n\(issue)", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(Palette.amber)
                    }
                    operationControls(recording)
                } else { Text("현재 보관함에 이 녹음이 없습니다. 돌아가서 새로고침하세요.").foregroundStyle(Palette.amber) }

                if let message = inspection.message, inspection.identity?.recordingID == recordingID {
                    Text(message).font(.caption).foregroundStyle(Palette.amber).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("container-check-message")
                }
                if let result = ownResult { resultView(result) }
                Card {
                    Text("검사 범위 및 리소스").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("단일 스트림 Opus v1, mapping 0, 1~2채널을 검사합니다. CRC, 페이지 순서, 패킷 경계와 granule 검증은 구조에만 적용되며 무선 전송의 완전성을 보장하지 않습니다.")
                    Text("64 KiB씩 읽으며 입력은 최대 64 MiB, 패킷은 최대 1 MiB입니다. 한도를 초과하면 중지합니다. 검사 작업은 한 번에 하나만 실행합니다.")
                    Text("화면을 나가면 검사와 결과를 취소합니다. 다시 들어와도 자동 검사하지 않습니다. 파일 변경 시 이전 결과는 무효이며 취소 후 리소스 해제를 기다려야 다시 시작할 수 있습니다.")
                }.font(.caption).foregroundStyle(Palette.muted)
            }.padding(24)
        }.background(Palette.background).navigationTitle("오디오 컨테이너 검사").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .onDisappear { inspection.leave(recordingID: recordingID) }
    }

    @ViewBuilder private func operationControls(_ recording: ArchivedRecording) -> some View {
        if ownResult != nil {
            PrimaryButton(title: "결과 지우고 다시 검사", icon: "arrow.counterclockwise") { inspection.clear() }
                .accessibilityIdentifier("container-clear")
            Text("화면의 결과만 지우며 오디오나 메모는 삭제하지 않습니다.").font(.caption2).foregroundStyle(Palette.muted)
        } else if !inspection.canStart {
            ProgressView(value: inspection.progress?.fraction ?? 0) {
                Text(inspection.phase == .preparing ? "로컬 보관 사본 검증 중…" : (inspection.phase == .reading ? "블록 단위 검사 중…" : "이전 작업 종료 대기 중…"))
            }.font(.caption).accessibilityIdentifier("container-progress")
            if let progress = inspection.progress {
                Text("\(ByteCountFormatter.string(fromByteCount: progress.bytesRead, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file))")
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
            Button("검사 취소") { inspection.cancel() }.font(.subheadline).accessibilityIdentifier("container-cancel")
        } else {
            PrimaryButton(title: "오디오 컨테이너 검사", icon: "waveform.path.ecg", enabled: issue == nil && !archive.isBusy) {
                inspection.start(AudioInspectionIdentity(recording))
            }.accessibilityIdentifier("container-start")
            if inspection.phase == .idle { Text("검사 전입니다. 화면을 열어도 오디오를 읽지 않습니다.").font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("container-idle") }
        }
    }

    private func resultView(_ result: AudioContainerCheckResult) -> some View {
        Card {
            Text(result.outcome.title).font(.headline).foregroundStyle(resultColor(result.outcome)).accessibilityIdentifier("container-outcome")
            Text("검사 시간: \(result.checkedAt.formatted(date: .abbreviated, time: .standard))")
                .font(.caption).foregroundStyle(Palette.muted)
            Text("검사한 스트림의 SHA-256이 보관 기록과 일치합니다. 이번 로컬 파일에만 해당합니다.").font(.caption2).foregroundStyle(Palette.muted)
            switch result.outcome {
            case .supported(let report):
                VStack(spacing: 10) {
                    metric("Ogg 페이지 / CRC 통과 페이지", "\(report.pageCount) / \(report.crcCheckedPages)")
                    metric("오디오 패킷 / 헤더 포함 패킷", "\(report.audioPacketCount) / \(report.packetCountIncludingHeaders)")
                    metric("BOS / EOS", "\(report.bosPresent ? "있음" : "없음") / \(report.eosPresent ? "있음" : "없음")")
                    metric("채널 / pre-skip", "\(report.opusHeader.channels) / \(report.opusHeader.preSkip)")
                    metric("처음 / 마지막 granule", "\(report.firstAudioGranule) / \(report.finalGranule)")
                    metric("마지막 PCM 위치", "\(report.finalPCMPosition)")
                    metric("48 kHz 기준 시간 위치", String(format: "%.4f초", report.finalPCMPositionSeconds))
                    metric("페이지 버퍼 최대 크기", "\(result.peakParserPageBytes)바이트")
                }
                Text("시간 위치는 실제 측정한 녹음 길이가 아니며 페이지 버퍼 크기는 앱 전체 메모리가 아닙니다. 실제 패킷 길이와 granule 증가량의 일치 여부는 검사하지 않았습니다.")
                    .font(.caption).foregroundStyle(Palette.amber)
            case .unsupported(let reason), .invalid(let reason), .limited(let reason):
                Text(reason).font(.subheadline).foregroundStyle(Palette.muted)
            }
            Text("디코딩 안 함 · ASR 안 함 · 업로드 안 함").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                .accessibilityIdentifier("container-no-asr")
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(Palette.muted); Spacer(minLength: 12)
            Text(value).foregroundStyle(Palette.ink).monospacedDigit()
        }.font(.caption)
    }
    private func resultColor(_ outcome: AudioContainerOutcome) -> Color {
        if case .supported = outcome { return Palette.green }
        return Palette.amber
    }
}
