import Foundation

/// UI summaries for metadata-only SDK logs. Original logs remain in NSLog.
/// External/user text is never passed through this formatter.
enum KoreanDiagnostics {
    static func display(_ text: String) -> String {
        let table: [(String, String)] = [
            ("Peer removed pairing information", "이전 페어링 정보 불일치 · iPhone 설정 → Bluetooth에서 안경을 지운 뒤 다시 연결하세요"),
            ("SDK 缓存匹配设备数=0", "연결할 안경이 없습니다. 페어링 모드로 전환한 뒤 검색하세요"),
            ("SDK 版本不匹配，拒绝加载", "통신 SDK 버전이 맞지 않아 로드를 중지했습니다"),
            ("SDK central 尚未就绪，请加载后重新扫描", "Bluetooth 통신 모듈 준비 중입니다. 잠시 후 다시 검색하세요"),
            ("SDK 广播解析未返回设备标识", "안경 식별 정보를 읽지 못했습니다"),
            ("扫描已验证的 B81D 服务", "안경 검색 중 (B81D 서비스)"),
            ("扫描结束", "안경 검색이 끝났습니다"),
            ("SDK BLE 请求已提交，等待设备认证状态", "Bluetooth 연결을 요청했습니다. 안경 인증을 기다립니다"),
            ("已绑定眼镜已认证连接，无需重连", "등록된 안경의 연결과 인증이 완료됐습니다"),
            ("SDK discoverStart 调用成功", "안경 검색 요청됨"),
            ("设备连接维护已开启", "등록된 안경 재연결 대기 중"),
            ("发现:", "안경 발견:"),
            ("系统已连 RayNeo 服务:", "시스템에 연결된 RayNeo:"),
            ("SDK BLE 连接错误:", "Bluetooth 연결 오류:"),
            ("持续服务管理连接中，请先关闭再手动连接", "음성 대기를 끈 뒤 수동 연결을 시도하세요"),
            ("先加载通信核心并发现眼镜", "통신 모듈을 준비하고 안경을 먼저 검색하세요"),
            ("没有已认证连接，未执行解绑", "인증된 연결이 없어 등록 해제를 실행하지 않았습니다"),
            ("BLE状态字节=", "BLE="),
            ("已由 SDK 自己的 CBCentralManager 解析外设对象", "안경 Bluetooth 정보를 읽었습니다"),
            ("SDK 广播解析成功，已取得协议设备标识（不显示原值）", "안경 식별 정보를 확인했습니다"),
            ("没有唯一已认证连接，未发消息", "인증된 안경이 없어 메시지를 보내지 않았습니다"),
            ("持续待命开启需要唯一已认证设备，请先连接", "음성 대기를 켜려면 안경 연결과 인증이 필요합니다"),
            ("缺少Keychain凭证", "필요한 API 키가 저장되지 않았습니다"),
            ("独立 SDK instance 已创建", "기기 통신 모듈을 준비했습니다")
        ]
        for (needle, replacement) in table where text.contains(needle) {
            // Preserve detailed English diagnostics for CoreBluetooth errors.
            if needle == "Peer removed pairing information" { return replacement + " (CBError 14)" }
            let value = text.replacingOccurrences(of: needle, with: replacement)
            if !containsHan(value) { return value }
            return replacement + diagnosticFields(text)
        }
        guard containsHan(text) else { return text }
        if text.contains("ASR") {
            return (text.contains("失败") || text.contains("异常") ? "음성 인식 서비스 오류" : "음성 인식 처리 상태 갱신") + diagnosticFields(text)
        }
        if text.contains("DeepSeek") || text.contains("模型") {
            return (text.contains("失败") || text.contains("异常") ? "AI 응답 서비스 오류" : "AI 응답 처리 상태 갱신") + diagnosticFields(text)
        }
        if text.contains("连接") { return "안경 연결 상태 갱신" + diagnosticFields(text) }
        return "기기 통신 진단" + diagnosticFields(text)
    }
    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }
    private static func diagnosticFields(_ text: String) -> String {
        let pattern = #"(?:SDK trace[^\r\n]*|(?:code|type|value|linkedCount|connected|attempt|characters|bytes|RSSI|BLE)=[-A-Za-z0-9_./]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let range = NSRange(text.startIndex..., in: text)
        let parts = regex.matches(in: text, range: range).compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            let value = String(text[range])
            return containsHan(value) ? nil : value
        }
        return parts.isEmpty ? "" : " · " + parts.prefix(4).joined(separator: " · ")
    }
}
