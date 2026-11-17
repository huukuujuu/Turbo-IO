import Foundation

/// Local bookkeeping only. These versions and observation times are never wire timestamps/ACKs.
struct TodoDelivery: Codable, Equatable {
    struct Observation: Codable, Equatable {
        var completed: Bool
        var important: Bool?
    }
    var revision = UUID()
    var pending = true
    var submittedRevision: UUID?
    var submittedAt: Date?
    var conflict: Observation?

    mutating func edited() { revision = UUID(); pending = true }
}

enum TodoDeliveryError: LocalizedError {
    case differentDevice, conflict, missing
    var errorDescription: String? {
        switch self {
        case .differentDevice: return "다른 안경에 연결된 할 일이 있어 전송하지 않았습니다. 안경 간 이전은 지원하지 않습니다."
        case .conflict: return "전송 대기 및 충돌 화면에서 상태 충돌을 먼저 처리하세요. 전송을 중지했습니다."
        case .missing: return "할 일이 제거됐거나 버전이 바뀌었습니다. 다시 확인한 뒤 보내세요."
        }
    }
}

extension LocalTodo {
    var deliveryDescription: String {
        if delivery?.conflict != nil { return "상태 충돌 · 로컬 변경 유지됨" }
        guard wireID != nil else { return completed ? "기기에서 완료됨 · 동기화 전" : "휴대폰에만 저장됨" }
        if delivery?.pending == true { return "전송 대기 · 로컬 변경 저장됨" }
        if delivery?.submittedAt != nil { return "전송됨 · 항목별 확인 전" }
        return "안경과 연결됨 · 안경 응답 기준"
    }
}
