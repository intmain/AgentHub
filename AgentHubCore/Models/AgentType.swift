import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// AI 에이전트 종류
public enum AgentType: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini
    case opencode
    case cursor

    public var id: String { rawValue }

    /// 표시 이름
    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .opencode: return "OpenCode"
        case .cursor: return "Cursor"
        }
    }

    /// 에이전트 아이콘 (SF Symbol)
    public var iconName: String {
        switch self {
        case .claude: return "circle.fill"
        case .codex: return "circle.fill"
        case .gemini: return "circle.fill"
        case .opencode: return "circle.fill"
        case .cursor: return "circle.fill"
        }
    }

    #if canImport(SwiftUI)
    /// 에이전트 색상
    public var color: Color {
        switch self {
        case .claude: return Color(red: 1.0, green: 0.42, blue: 0.21)  // #FF6B35
        case .codex: return Color(red: 0, green: 0.82, blue: 0.42)     // #00D26A
        case .gemini: return Color(red: 0.26, green: 0.52, blue: 0.96) // #4285F4
        case .opencode: return Color(red: 0.61, green: 0.35, blue: 0.71) // #9B59B6
        case .cursor: return Color.gray
        }
    }
    #endif

    /// ANSI 색상 코드 (CLI용)
    public var ansiColor: String {
        switch self {
        case .claude: return "\u{001B}[38;5;208m"   // 오렌지
        case .codex: return "\u{001B}[38;5;40m"     // 녹색
        case .gemini: return "\u{001B}[38;5;33m"    // 파랑
        case .opencode: return "\u{001B}[38;5;135m" // 보라
        case .cursor: return "\u{001B}[38;5;245m"   // 회색
        }
    }

    /// 로그 파일 기본 경로
    public var logPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .claude:
            return "\(home)/.claude/projects"
        case .codex:
            return "\(home)/.codex/sessions"
        case .gemini:
            return "\(home)/.gemini"
        case .opencode:
            return "\(home)/.local/share/opencode/storage"
        case .cursor:
            return "\(home)/Library/Application Support/Cursor/logs"
        }
    }
}
