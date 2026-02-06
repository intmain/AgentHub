import Foundation

/// 세션 데이터 캐시 (App Group Container 기반 공유 - 앱과 위젯 간)
public class SessionCache {
    public static let shared = SessionCache()

    // App Group ID (엔타이틀먼트의 $(TeamIdentifierPrefix)group.com.agenthub 에 대응)
    private let appGroupId = "8LHHKYA787.group.com.agenthub"

    private let sessionsFileName = "sessions.json"
    private let summaryFileName = "summary.json"
    private let lastUpdatedFileName = "last_updated"

    /// App Group Container 디렉토리
    /// 샌드박스된 위젯과 메인 앱 모두 접근 가능
    private var cacheDirectory: URL {
        if let groupContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            return groupContainer
        }
        // Fallback: App Group이 동작하지 않을 경우
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AgentHub")
    }

    private init() {
        ensureCacheDirectoryExists()
    }

    private func ensureCacheDirectoryExists() {
        let fm = FileManager.default
        let dir = cacheDirectory
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Sessions

    /// 세션 저장 (활성 세션만)
    public func save(sessions: [AgentSession]) {
        ensureCacheDirectoryExists()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        // 활성 세션만 저장
        let activeSessions = sessions.filter { $0.status.isActive }

        // 세션 파일 저장
        if let data = try? encoder.encode(activeSessions) {
            let sessionsURL = cacheDirectory.appendingPathComponent(sessionsFileName)
            try? data.write(to: sessionsURL, options: .atomic)
        }

        // 요약 정보 저장
        let summary = createSummary(from: activeSessions)
        if let summaryData = try? encoder.encode(summary) {
            let summaryURL = cacheDirectory.appendingPathComponent(summaryFileName)
            try? summaryData.write(to: summaryURL, options: .atomic)
        }

        // 마지막 갱신 시간 저장
        let timestampURL = cacheDirectory.appendingPathComponent(lastUpdatedFileName)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try? timestamp.write(to: timestampURL, atomically: true, encoding: .utf8)
    }

    /// 세션 로드
    public func loadSessions() -> [AgentSession] {
        let sessionsURL = cacheDirectory.appendingPathComponent(sessionsFileName)

        guard let data = try? Data(contentsOf: sessionsURL) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return (try? decoder.decode([AgentSession].self, from: data)) ?? []
    }

    /// 요약 로드 (위젯용)
    public func loadSummary() -> CachedSummary? {
        let summaryURL = cacheDirectory.appendingPathComponent(summaryFileName)

        guard let data = try? Data(contentsOf: summaryURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(CachedSummary.self, from: data)
    }

    /// 마지막 갱신 시간
    public var lastUpdated: Date? {
        let timestampURL = cacheDirectory.appendingPathComponent(lastUpdatedFileName)
        guard let str = try? String(contentsOf: timestampURL, encoding: .utf8) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: str)
    }

    // MARK: - Private

    private func createSummary(from activeSessions: [AgentSession]) -> CachedSummary {
        return CachedSummary(
            activeCount: activeSessions.count,
            totalCount: activeSessions.count,
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
