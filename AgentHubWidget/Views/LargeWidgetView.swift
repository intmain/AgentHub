import SwiftUI
import WidgetKit

/// 큰 위젯 - 전체 세션 목록
struct LargeWidgetView: View {
    let entry: SessionEntry

    var body: some View {
        VStack(spacing: 12) {
            // 헤더
            headerSection

            Divider()

            // 세션 목록
            if entry.sessions.isEmpty {
                emptyState
            } else {
                sessionsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text("AgentHub")
                    .font(.system(size: 14, weight: .semibold))
            }

            Spacer()

            // 통계
            HStack(spacing: 12) {
                StatBadge(
                    icon: "bolt.fill",
                    value: "\(entry.summary?.activeCount ?? 0)",
                    color: .green
                )

                StatBadge(
                    icon: "dollarsign.circle.fill",
                    value: entry.summary?.formattedCost ?? "$0",
                    color: .orange
                )

                StatBadge(
                    icon: "number.circle.fill",
                    value: entry.summary?.formattedTokens ?? "0",
                    color: .blue
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text("세션 없음")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionsList: some View {
        VStack(spacing: 6) {
            ForEach(entry.sessions.prefix(5)) { session in
                LargeWidgetSessionRow(session: session)
            }

            if entry.sessions.count > 5 {
                Text("외 \(entry.sessions.count - 5)개")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
        }
    }
}

// MARK: - Large Widget Session Row

struct LargeWidgetSessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 8) {
            // 에이전트 색상
            Circle()
                .fill(session.agent.color)
                .frame(width: 8, height: 8)

            // 상태
            Image(systemName: session.status.sfSymbol)
                .font(.system(size: 10))
                .foregroundColor(session.status.color)

            // 프로젝트명
            Text(session.projectName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer()

            // 토큰
            Text(session.formattedTokens)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .monospacedDigit()

            // 비용
            Text(session.formattedCost)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.orange)
                .monospacedDigit()

            // 시간
            Text(session.timeSinceLastActivity)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview(as: .systemLarge) {
    AgentHubWidget()
} timeline: {
    SessionEntry(
        date: Date(),
        summary: CachedSummary(
            activeCount: 3,
            totalCount: 6,
            totalCost: 2.15,
            totalTokens: 185000,
            topSessions: [],
            lastUpdated: Date()
        ),
        sessions: [
            AgentSession(
                id: "1",
                agent: .claude,
                projectPath: "/test",
                projectName: "agenthub",
                status: .running,
                tokens: TokenUsage(input: 50000, output: 15000),
                cost: 0.75
            ),
            AgentSession(
                id: "2",
                agent: .gemini,
                projectPath: "/test2",
                projectName: "web-app",
                status: .waiting,
                tokens: TokenUsage(input: 20000, output: 8000),
                cost: 0.25
            ),
            AgentSession(
                id: "3",
                agent: .codex,
                projectPath: "/test3",
                projectName: "cli-tool",
                status: .idle,
                tokens: TokenUsage(input: 10000, output: 3000),
                cost: 0.15
            )
        ]
    )
}
