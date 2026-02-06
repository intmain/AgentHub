import WidgetKit
import SwiftUI

/// 위젯 타임라인 엔트리
struct SessionEntry: TimelineEntry {
    let date: Date
    let summary: CachedSummary?
    let sessions: [AgentSession]
}

/// 위젯 타임라인 프로바이더
struct SessionTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionEntry {
        SessionEntry(
            date: Date(),
            summary: CachedSummary(
                activeCount: 2,
                totalCount: 5,
                totalCost: 0.35,
                totalTokens: 45000,
                topSessions: [],
                lastUpdated: Date()
            ),
            sessions: []
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionEntry) -> Void) {
        let entry = loadEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionEntry>) -> Void) {
        let entry = loadEntry()

        // 5분 후 갱신
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    private func loadEntry() -> SessionEntry {
        let cache = SessionCache.shared

        // 파일 기반 캐시에서 데이터 로드 (에러 시 빈 데이터 반환)
        let summary = cache.loadSummary()
        let sessions = cache.loadSessions()

        // 캐시가 30분 이상 오래된 경우 stale로 간주
        if let lastUpdated = cache.lastUpdated,
           Date().timeIntervalSince(lastUpdated) > 1800 {
            // stale 데이터: 요약의 lastUpdated를 그대로 사용하여 UI에서 표시 가능
            return SessionEntry(
                date: Date(),
                summary: summary,
                sessions: sessions
            )
        }

        return SessionEntry(
            date: Date(),
            summary: summary,
            sessions: sessions
        )
    }
}
