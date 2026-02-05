import Foundation

/// 세션 데이터 캐시 (App Group 공유)
public class SessionCache {
    public static let shared = SessionCache()

    // App Group ID (앱과 위젯 간 공유)
    private let appGroupId = "group.com.agenthub"
    private let sessionsKey = "cached_sessions"
    private let summaryKey = "cached_summary"
    private let lastUpdatedKey = "cache_last_updated"

    private var userDefaults: UserDefaults {
        // App Group이 설정되지 않은 경우 standard UserDefaults 사용
        if let groupDefaults = UserDefaults(suiteName: appGroupId) {
            return groupDefaults
        }
        return UserDefaults.standard
    }

    private init() {}

    // MARK: - Sessions

    /// 세션 저장 (활성 세션만)
    public func save(sessions: [AgentSession]) {
        let defaults = userDefaults
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // 활성 세션만 저장
        let activeSessions = sessions.filter { $0.status.isActive }

        if let data = try? encoder.encode(activeSessions) {
            defaults.set(data, forKey: sessionsKey)
            defaults.set(Date(), forKey: lastUpdatedKey)
        }

        // 요약 정보도 저장 (활성 세션 기준)
        let summary = createSummary(from: activeSessions)
        if let summaryData = try? encoder.encode(summary) {
            defaults.set(summaryData, forKey: summaryKey)
        }
    }

    /// 세션 로드
    public func loadSessions() -> [AgentSession] {
        guard let data = userDefaults.data(forKey: sessionsKey) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return (try? decoder.decode([AgentSession].self, from: data)) ?? []
    }

    /// 요약 로드 (위젯용)
    public func loadSummary() -> CachedSummary? {
        guard let data = userDefaults.data(forKey: summaryKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(CachedSummary.self, from: data)
    }

    /// 마지막 갱신 시간
    public var lastUpdated: Date? {
        userDefaults.object(forKey: lastUpdatedKey) as? Date
    }

    // MARK: - Private

    private func createSummary(from activeSessions: [AgentSession]) -> CachedSummary {
        return CachedSummary(
            activeCount: activeSessions.count,
            totalCount: activeSessions.count,  // 활성 세션만 표시
            totalCost: CostCalculator.totalCost(sessions: activeSessions),
            totalTokens: CostCalculator.totalTokens(sessions: activeSessions).total,
            topSessions: Array(activeSessions.prefix(3)),
            lastUpdated: Date()
        )
    }
}

// MARK: - Cached Summary

public struct CachedSummary: Codable {
    public let activeCount: Int
    public let totalCount: Int
    public let totalCost: Double
    public let totalTokens: Int
    public let topSessions: [AgentSession]
    public let lastUpdated: Date

    public var formattedCost: String {
        CostCalculator.formatCost(totalCost)
    }

    public var formattedTokens: String {
        CostCalculator.formatTokens(totalTokens)
    }
}
