import Foundation
import AVFoundation
import Combine
import SwiftUI

enum RecordingASRError: LocalizedError {
    case unsupported, limit, credentials, remote, empty
    var errorDescription: String? {
        switch self {
        case .unsupported: return "iOS에서 디코딩할 수 없는 오디오입니다. WAV, M4A, MP3 등 지원 형식을 사용하세요. 안경 원시 파일은 별도 변환이 필요할 수 있습니다."
        case .limit: return "수동 전사는 최대 10분 오디오 / 디코딩된 PCM 32 MiB까지 지원합니다."
        case .credentials: return "음성 AI 연결 설정에서 Alibaba Cloud ASR 키를 먼저 저장하세요. 시뮬레이터는 실제 서비스를 호출하지 않습니다."
        case .remote: return "ASR 연결, 시간 초과 또는 프로토콜 오류 · 전사 성공으로 저장하지 않았습니다. 재시도할 수 있습니다."
        case .empty: return "ASR이 유효한 최종 텍스트를 반환하지 않아 빈 메모를 만들지 않았습니다."
        }
    }
}

enum RecordingPCMDecoder {
    static func decode(_ url: URL, inputChannel: Int? = nil, diagnostic: (String) -> Void = { _ in }) throws -> Data {
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) } catch { diagnostic("open-failed"); throw RecordingASRError.unsupported }
        let format = input.processingFormat
        guard format.sampleRate.isFinite, format.sampleRate > 0, input.length > 0,
              format.channelCount > 0, format.channelCount <= 32,
              Double(input.length) / format.sampleRate <= 600 else { throw RecordingASRError.limit }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: monoFormat, to: target),
              let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192),
              let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: 8192),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) else { diagnostic("converter-init-failed"); throw RecordingASRError.unsupported }
        if let channel = inputChannel {
            guard channel >= 0, channel < Int(format.channelCount) else { throw RecordingASRError.unsupported }
        }
        var pcm = Data(), failed = false
        for _ in 0..<10_000 {
            try Task.checkCancellation()
            var error: NSError?
            let result = converter.convert(to: output, error: &error) { requested, status in
                do {
                    let remaining = input.length - input.framePosition
                    guard remaining > 0 else { status.pointee = .endOfStream; return nil }
                    let count = min(requested, source.frameCapacity, AVAudioFrameCount(min(remaining, Int64(UInt32.max))))
                    try input.read(into: source, frameCount: count)
                    try mixToMono(source, into: mono, inputChannel: inputChannel)
                    status.pointee = source.frameLength == 0 ? .endOfStream : .haveData
                    return source.frameLength == 0 ? nil : mono
                } catch { failed = true; status.pointee = .endOfStream; return nil }
            }
            guard !failed, error == nil, result != .error else { diagnostic("convert-failed read=\(failed) status=\(result.rawValue) code=\(error?.code ?? 0)"); throw RecordingASRError.unsupported }
            if output.frameLength > 0, let samples = output.int16ChannelData {
                guard pcm.count + Int(output.frameLength) * 2 <= 32 * 1_024 * 1_024 else { throw RecordingASRError.limit }
                pcm.append(UnsafeRawPointer(samples[0]).assumingMemoryBound(to: UInt8.self), count: Int(output.frameLength) * 2)
            }
            if result == .endOfStream {
                guard !pcm.isEmpty else { throw RecordingASRError.empty }
                return pcm
            }
        }
        throw RecordingASRError.limit
    }

    /// Explicit equal-weight downmix before resampling. AVAudioConverter's
    /// default channel mapping can select channel 0 instead of mixing stereo.
    /// Average rather than sum so full-scale in-phase channels cannot overflow.
    private static func mixToMono(_ source: AVAudioPCMBuffer, into mono: AVAudioPCMBuffer, inputChannel: Int?) throws {
        guard let input = source.floatChannelData, let output = mono.floatChannelData,
              source.frameLength <= mono.frameCapacity else { throw RecordingASRError.unsupported }
        let channels = Int(source.format.channelCount)
        let selected = inputChannel.map { $0..<($0 + 1) } ?? (0..<channels)
        for frame in 0..<Int(source.frameLength) {
            var sum = 0.0
            for channel in selected {
                let value = Double(input[channel][frame])
                guard value.isFinite else { throw RecordingASRError.unsupported }
                sum += value
            }
            output[0][frame] = Float(max(-1, min(1, sum / Double(selected.count))))
        }
        mono.frameLength = source.frameLength
    }
}

struct FileASRAccumulator {
    private var sentences: [Int: String] = [:]
    mutating func accept(id: Int, text: String, final: Bool) throws {
        guard id >= 0, id <= 100_000, text.utf8.count <= 16_384 else { throw RecordingASRError.remote }
        guard final else { return }
        guard sentences.count < 6_000 || sentences[id] != nil else { throw RecordingASRError.limit }
        sentences[id] = text
        guard sentences.values.reduce(0, { $0 + $1.utf8.count }) <= 1_024 * 1_024 else { throw RecordingASRError.limit }
    }
    var text: String { sentences.keys.sorted().compactMap { sentences[$0] }.filter { !$0.isEmpty }.joined(separator: "\n") }
}

private final class FileASRNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Explicit per-run local capture. No headers; redact the configured secret if
/// it is unexpectedly echoed by a remote error. The source recording is untouched.
final class FileASRDiagnostic {
    let directory: URL
    private let secret: String
    private let handle: FileHandle
    private var size = 0
    init(root: URL, pcm: Data, secret: String) throws {
        self.secret = secret
        directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try pcm.write(to: directory.appendingPathComponent("sent-16000-mono-s16le.pcm"), options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
        let events = directory.appendingPathComponent("events.jsonl")
        guard FileManager.default.createFile(atPath: events.path, contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw RecordingASRError.remote }
        handle = try FileHandle(forWritingTo: events)
    }
    deinit { try? handle.close() }
    func record(_ event: String, _ body: String) throws {
        let safe = secret.isEmpty ? body : body.replacingOccurrences(of: secret, with: "[REDACTED]")
        var line = try JSONSerialization.data(withJSONObject: ["time": Date().timeIntervalSince1970, "event": event, "body": safe], options: [.sortedKeys])
        line.append(10)
        guard size + line.count <= 2_097_152 else { throw RecordingASRError.limit }
        try handle.write(contentsOf: line); try handle.synchronize()
        size += line.count
    }
}

@MainActor enum FileASRClient {
    // DashScope controls are UTF-8 text frames; only PCM is binary.
    static func controlMessage(_ object: [String: Any]) throws -> URLSessionWebSocketTask.Message {
        .string(String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    static func transcribe(pcm: Data, key: String, host: String, diagnostic: FileASRDiagnostic? = nil, progress: @escaping (Double) -> Void) async throws -> String {
        guard let host = CloudASRHostSettings.normalize(host) else { throw RecordingASRError.credentials }
        guard !pcm.isEmpty, pcm.count % 2 == 0, pcm.count <= 32 * 1_024 * 1_024 else { throw RecordingASRError.limit }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 660
        let session = URLSession(configuration: config, delegate: FileASRNoRedirect(), delegateQueue: nil)
        // The caller captures this host with its host-scoped credential before decoding.
        var request = URLRequest(url: URL(string: "wss://\(host)/api-ws/v1/inference")!)
        request.setValue("bearer " + key, forHTTPHeaderField: "Authorization")
        let ws = session.webSocketTask(with: request); ws.maximumMessageSize = 65_536
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var sender: Task<Void, Error>?
        let watchdog = Task {
            try await Task.sleep(nanoseconds: UInt64(Double(pcm.count) / 32_000 + 40) * 1_000_000_000)
            ws.cancel(with: .goingAway, reason: nil)
        }
        defer { watchdog.cancel(); sender?.cancel(); ws.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
        ws.resume()
        return try await withTaskCancellationHandler {
            let run: [String: Any] = ["header": ["action": "run-task", "task_id": id, "streaming": "duplex"],
                "payload": ["task_group": "audio", "task": "asr", "function": "recognition", "model": "qwen-audio-3.0-asr-flash-streaming",
                            "parameters": ["format": "pcm", "sample_rate": 16000,
                                           "language_hints": ["ko", "en"]], "input": [:]]]
            try diagnostic?.record("run-task", String(decoding: JSONSerialization.data(withJSONObject: run), as: UTF8.self))
            try await ws.send(controlMessage(run))
            var accumulator = FileASRAccumulator(), sentAll = false, events = 0
            while !Task.isCancelled {
                let message = try await ws.receive()
                let data: Data
                switch message { case .data(let bytes): data = bytes; case .string(let text): data = Data(text.utf8); @unknown default: throw RecordingASRError.remote }
                try diagnostic?.record("received", String(decoding: data, as: UTF8.self))
                events += 1
                guard events <= 30_000, data.count <= 65_536,
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let header = object["header"] as? [String: Any], header["task_id"] as? String == id else { throw RecordingASRError.remote }
                switch header["event"] as? String {
                case "task-started":
                    guard sender == nil else { throw RecordingASRError.remote }
                    sender = Task { @MainActor in
                        do {
                            for offset in stride(from: 0, to: pcm.count, by: 3200) {
                                try Task.checkCancellation()
                                let end = min(pcm.count, offset + 3200)
                                try await ws.send(.data(pcm.subdata(in: offset..<end)))
                                progress(Double(end) / Double(pcm.count))
                                try await Task.sleep(nanoseconds: 100_000_000)
                            }
                            sentAll = true
                            try diagnostic?.record("sent-audio", "bytes=\(pcm.count) sample_rate=16000 channels=1 format=s16le")
                            try await ws.send(controlMessage(["header": ["action": "finish-task", "task_id": id, "streaming": "duplex"], "payload": ["input": [:]]]))
                        } catch { ws.cancel(with: .goingAway, reason: nil); throw error }
                    }
                case "result-generated":
                    if let payload = object["payload"] as? [String: Any], let output = payload["output"] as? [String: Any],
                       let sentence = output["sentence"] as? [String: Any], sentence["heartbeat"] as? Bool != true,
                       let number = sentence["sentence_id"] as? NSNumber, number.doubleValue == Double(number.intValue),
                       let text = sentence["text"] as? String {
                        try accumulator.accept(id: number.intValue, text: text, final: sentence["sentence_end"] as? Bool == true)
                    }
                case "task-finished":
                    guard sentAll else { throw RecordingASRError.remote }
                    try await sender?.value
                    let text = accumulator.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    try diagnostic?.record("parsed-final", "characters=\(text.count)")
                    guard !text.isEmpty else { throw RecordingASRError.empty }
                    return text
                case "task-failed": throw RecordingASRError.remote
                default: break
                }
            }
            throw CancellationError()
        } onCancel: { ws.cancel(with: .goingAway, reason: nil) }
    }
}

@MainActor final class ManualRecordingASR: ObservableObject {
    @Published private(set) var recordingID: UUID?
    @Published private(set) var progress = 0.0
    @Published private(set) var status = ""
    @Published private(set) var resultText = ""
    @Published private var work: Task<Void, Never>?
    var busy: Bool { work != nil }
    func cancel() { work?.cancel(); status = "취소 중 · 원본 오디오는 유지됩니다…" }
    func start(id: UUID, title: String, archive: LocalArchiveController, captureDiagnostic: Bool = false, rightChannelOnly: Bool = false) {
        guard work == nil else { return }
        recordingID = id; progress = 0; resultText = ""
        #if COMPANION_DEVICE
        guard let host = CloudASRHostSettings.normalize(CloudVoiceKeys.asrHost),
              let key = CloudVoiceKeys.get(CloudASRHostSettings.service(for: host)) else { status = RecordingASRError.credentials.localizedDescription; return }
        work = Task { @MainActor in
            defer { work = nil }
            var diagnostic: FileASRDiagnostic?
            do {
                status = "로컬 오디오 검증 중…"
                guard let url = await archive.verify(id) else { throw RecordingASRError.unsupported }
                try Task.checkCancellation()
                status = "기기에서 16 kHz 모노로 디코딩 중…"
                let decoder = Task.detached(priority: .userInitiated) { try RecordingPCMDecoder.decode(url, inputChannel: rightChannelOnly ? 1 : nil) }
                let pcm = try await withTaskCancellationHandler { try await decoder.value } onCancel: { decoder.cancel() }
                try Task.checkCancellation()
                if captureDiagnostic {
                    let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    diagnostic = try FileASRDiagnostic(root: root.appendingPathComponent("ManualASRDiagnosticsV1"), pcm: pcm, secret: key)
                    try diagnostic?.record("source", "recording=\(id.uuidString) decodedBytes=\(pcm.count) channel=\(rightChannelOnly ? "right-only" : "equal-weight-downmix")")
                }
                status = "전사 중 · 오디오를 Alibaba Cloud로 전송 중…"
                let text = try await FileASRClient.transcribe(pcm: pcm, key: key, host: host, diagnostic: diagnostic) { value in self.progress = value }
                try Task.checkCancellation()
                resultText = text
                status = "새 텍스트 수정본 저장 중…"
                guard await archive.saveTranscript(recordingID: id, text: text, title: String(("ASR · " + title).prefix(64))) != nil else {
                    status = "인식은 끝났지만 메모를 저장하지 못했습니다. 아래 텍스트를 복사할 수 있으며 원본 오디오는 유지됩니다."; return
                }
                status = "전사 완료 · 새 Markdown 수정본으로 저장했습니다. 인식 내용을 확인하세요."
            } catch is CancellationError { status = "후속 처리를 취소했습니다. 원본 오디오와 이미 저장된 수정본은 유지됩니다." }
            catch {
                try? diagnostic?.record("client-error", "domain=\((error as NSError).domain) code=\((error as NSError).code) description=\(error.localizedDescription)")
                status = (error as? RecordingASRError)?.localizedDescription ?? "전사를 완료하지 못했습니다. 네트워크 중단 또는 취소됐을 수 있으며 원본 오디오는 유지됩니다."
            }
        }
        #else
        status = RecordingASRError.credentials.localizedDescription
        #endif
    }
}

struct ManualRecordingASRView: View {
    let id: UUID, title: String
    @EnvironmentObject private var asr: ManualRecordingASR
    @EnvironmentObject private var archive: LocalArchiveController
    @State private var confirmation = false
    @State private var captureDiagnostic = false
    @State private var rightChannelOnly = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("녹음 텍스트 변환").font(.headline)
            Text("확인 후에만 이 오디오를 Alibaba Cloud ASR로 전송합니다. 오디오 길이에 따라 요금이 발생할 수 있습니다. DeepSeek나 자동 요약은 사용하지 않습니다. 성공하면 새 텍스트 수정본을 만들며 원본은 유지합니다.")
                .font(.caption).foregroundStyle(Palette.muted)
            Text("전사 중에는 앱 화면을 열어 두세요. 장시간 백그라운드 동작은 검증되지 않았습니다.").font(.caption2).foregroundStyle(Palette.muted)
            Text("기본적으로 모든 채널을 합쳐 16 kHz 모노로 변환합니다. 원본 녹음은 유지합니다.").font(.caption2).foregroundStyle(Palette.muted)
            Toggle("다음 실행의 ASR 진단 저장", isOn: $captureDiagnostic).disabled(asr.busy).accessibilityIdentifier("manual-asr-diagnostic")
            if captureDiagnostic { Text("전송한 오디오와 서버 응답(전사 텍스트 포함 가능)을 기기에 추가 저장합니다. 요청 헤더나 API 키는 기록하지 않습니다.").font(.caption2) }
            if captureDiagnostic {
                Toggle("진단: 이번만 오른쪽 채널 사용", isOn: $rightChannelOnly).disabled(asr.busy).accessibilityIdentifier("manual-asr-right-channel")
            }
            Button("ASR 전사 시작") { confirmation = true }.disabled(asr.busy || archive.isBusy).accessibilityIdentifier("manual-recording-asr")
            if asr.recordingID == id {
                Text(asr.status).font(.caption)
                if asr.busy { ProgressView(value: asr.progress); Button("전사 취소") { asr.cancel() } }
                if !asr.resultText.isEmpty { Text(asr.resultText).font(.caption).textSelection(.enabled).privacySensitive() }
            } else if asr.busy { Text("다른 녹음을 전사 중입니다. 완료 후 다시 시도하세요.").font(.caption) }
        }.confirmationDialog("이 녹음을 Alibaba Cloud ASR로 보낼까요? 요금이 발생할 수 있으며 인식 결과는 직접 확인해야 합니다.", isPresented: $confirmation) {
            Button("업로드 및 텍스트 변환 확인") {
                let capture = captureDiagnostic, right = captureDiagnostic && rightChannelOnly
                captureDiagnostic = false; rightChannelOnly = false
                asr.start(id: id, title: title, archive: archive, captureDiagnostic: capture, rightChannelOnly: right)
            }
        }
    }
}
