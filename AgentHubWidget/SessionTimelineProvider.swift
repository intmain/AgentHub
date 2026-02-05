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
        let summary = cache.loadSummary()
        let sessions = cache.loadSessions()

        return SessionEntry(
            date: Date(),
            summary: summary,
            sessions: sessions
        )
    }
}
