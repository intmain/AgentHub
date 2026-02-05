import Foundation

/// 토큰 사용량 정보
public struct TokenUsage: Codable, Equatable {
    public var input: Int
    public var output: Int
    public var total: Int
    public var cacheRead: Int?
    public var cacheWrite: Int?

    public init(input: Int = 0, output: Int = 0, cacheRead: Int? = nil, cacheWrite: Int? = nil) {
        self.input = input
        self.output = output
        self.total = input + output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
}

/// 에이전트 세션 정보
public struct AgentSession: Identifiable, Codable, Equatable, Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public let id: String
    public let agent: AgentType
    public var projectPath: String
    public var projectName: String
    public var status: SessionStatus
    public var pid: Int?
    public var tty: String?

    // 토큰/비용 정보
    public var tokens: TokenUsage
    public var cost: Double

    // 시간 정보
    public var startedAt: Date
    public var lastActivityAt: Date
    public var duration: TimeInterval  // seconds

    // 추가 메타데이터
    public var model: String?
    public var conversationId: String?
    public var logFilePath: String?

    public init(
        id: String,
        agent: AgentType,
        projectPath: String,
        projectName: String,
        status: SessionStatus = .idle,
        pid: Int? = nil,
        tty: String? = nil,
        tokens: TokenUsage = TokenUsage(),
        cost: Double = 0,
        startedAt: Date = Date(),
        lastActivityAt: Date = Date(),
        duration: TimeInterval = 0,
        model: String? = nil,
        conversationId: String? = nil,
        logFilePath: String? = nil
    ) {
        self.id = id
        self.agent = agent
        self.projectPath = projectPath
        self.projectName = projectName
        self.status = status
        self.pid = pid
        self.tty = tty
        self.tokens = tokens
        self.cost = cost
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.duration = duration
        self.model = model
        self.conversationId = conversationId
        self.logFilePath = logFilePath
    }
}

extension AgentSession {
    /// 포맷된 비용 문자열
    public var formattedCost: String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        } else if cost < 1 {
            return String(format: "$%.2f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }

    /// 포맷된 토큰 수
    public var formattedTokens: String {
        let total = tokens.total
        if total >= 1_000_000 {
            return String(format: "%.1fM", Double(total) / 1_000_000)
        } else if total >= 1_000 {
            return String(format: "%.1fK", Double(total) / 1_000)
        } else {
            return "\(total)"
        }
    }

    /// 포맷된 시간
    public var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// 마지막 활동으로부터 경과 시간
    public var timeSinceLastActivity: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastActivityAt, relativeTo: Date())
    }
}
