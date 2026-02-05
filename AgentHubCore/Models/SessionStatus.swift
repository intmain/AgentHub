import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// 세션 상태
public enum SessionStatus: String, Codable, CaseIterable {
    case running    // 활성 실행 중
    case waiting    // 사용자 입력 대기
    case completed  // 완료됨
    case error      // 오류 발생
    case idle       // 유휴 상태

    /// 상태 아이콘
    public var icon: String {
        switch self {
        case .running: return "●"
        case .waiting: return "◐"
        case .completed: return "✓"
        case .error: return "✗"
        case .idle: return "○"
        }
    }

    /// SF Symbol 이름
    public var sfSymbol: String {
        switch self {
        case .running: return "circle.fill"
        case .waiting: return "circle.lefthalf.filled"
        case .completed: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .idle: return "circle"
        }
    }

    #if canImport(SwiftUI)
    /// 상태 색상
    public var color: Color {
        switch self {
        case .running: return .green
        case .waiting: return .yellow
        case .completed: return .gray
        case .error: return .red
        case .idle: return .gray
        }
    }
    #endif

    /// ANSI 색상 코드 (CLI용)
    public var ansiColor: String {
        switch self {
        case .running: return "\u{001B}[32m"   // 녹색
        case .waiting: return "\u{001B}[33m"   // 노랑
        case .completed: return "\u{001B}[90m" // 회색
        case .error: return "\u{001B}[31m"     // 빨강
        case .idle: return "\u{001B}[90m"      // 회색
        }
    }

    /// 활성 상태 여부
    public var isActive: Bool {
        switch self {
        case .running, .waiting: return true
        default: return false
        }
    }
}
