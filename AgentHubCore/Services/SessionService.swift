import Foundation
import Combine

/// 통합 세션 관리 서비스
public class SessionService: ObservableObject {
    public static let shared = SessionService()

    // 파서들
    private let claudeParser = ClaudeLogParser()
    private let codexParser = CodexLogParser()
    private let geminiParser = GeminiLogParser()

    // 파일 감시
    private var fileWatcher: FileWatcher?

    // 갱신 타이머
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // 세션 데이터
    @Published public private(set) var sessions: [AgentSession] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastUpdated: Date?

    // 설정
    public var refreshInterval: TimeInterval = 30.0  // 30초

    private init() {
        setupFileWatcher()
        startRefreshTimer()
        refresh()
    }

    deinit {
        stopRefreshTimer()
        fileWatcher?.stop()
    }

    // MARK: - Public Methods

    /// 수동 새로고침
    public func refresh() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var allSessions: [AgentSession] = []

            // Claude 세션
            let claudeSessions = self.claudeParser.getAllSessions()
            allSessions.append(contentsOf: claudeSessions)

            // Codex 세션
            let codexSessions = self.codexParser.getAllSessions()
            allSessions.append(contentsOf: codexSessions)

            // Gemini 세션
            let geminiSessions = self.geminiParser.getAllSessions()
            allSessions.append(contentsOf: geminiSessions)

            // 최근 활동 순 정렬
            allSessions.sort { $0.lastActivityAt > $1.lastActivityAt }

            DispatchQueue.main.async {
                self.sessions = allSessions
                self.lastUpdated = Date()
                self.isLoading = false

                // 캐시 저장
                SessionCache.shared.save(sessions: allSessions)
            }
        }
    }

    // MARK: - Computed Properties

    /// 활성 세션만
    public var activeSessions: [AgentSession] {
        sessions.filter { $0.status.isActive }
    }

    /// 에이전트별 세션
    public func sessions(for agent: AgentType) -> [AgentSession] {
        sessions.filter { $0.agent == agent }
    }

    /// 전체 비용
    public var totalCost: Double {
        CostCalculator.totalCost(sessions: sessions)
    }

    /// 전체 토큰
    public var totalTokens: TokenUsage {
        CostCalculator.totalTokens(sessions: sessions)
    }

    /// 에이전트별 통계
    public var agentStats: [AgentType: (count: Int, cost: Double)] {
        var stats: [AgentType: (count: Int, cost: Double)] = [:]

        for agent in AgentType.allCases {
            let agentSessions = sessions(for: agent)
            let cost = CostCalculator.totalCost(sessions: agentSessions)
            stats[agent] = (agentSessions.count, cost)
        }

        return stats
    }

    // MARK: - Private Methods

    private func setupFileWatcher() {
        var paths: [String] = []

        for agent in [AgentType.claude, .codex, .gemini] {
            let path = agent.logPath
            if FileManager.default.fileExists(atPath: path) {
                paths.append(path)
            }
        }

        guard !paths.isEmpty else { return }

        fileWatcher = FileWatcher(paths: paths) { [weak self] in
            // 파일 변경 감지 시 갱신 (debounce)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refresh()
            }
        }
        fileWatcher?.start()
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Summary Data

extension SessionService {
    /// 요약 데이터 (위젯용)
    public struct Summary: Codable {
        public let activeCount: Int
        public let totalCount: Int
        public let totalCost: Double
        public let totalTokens: Int
        public let lastUpdated: Date

        public var formattedCost: String {
            CostCalculator.formatCost(totalCost)
        }

        public var formattedTokens: String {
            CostCalculator.formatTokens(totalTokens)
        }
    }

    public var summary: Summary {
        Summary(
            activeCount: activeSessions.count,
            totalCount: sessions.count,
            totalCost: totalCost,
            totalTokens: totalTokens.total,
            lastUpdated: lastUpdated ?? Date()
        )
    }
}
