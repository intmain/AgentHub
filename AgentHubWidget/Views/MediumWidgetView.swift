import SwiftUI
import WidgetKit

/// 중간 위젯 - 요약 + 상위 2개 세션
struct MediumWidgetView: View {
    let entry: SessionEntry

    var body: some View {
        HStack(spacing: 16) {
            // 왼쪽: 요약
            summarySection

            Divider()

            // 오른쪽: 상위 세션
            sessionsSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summarySection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text("AgentHub")
                    .font(.system(size: 12, weight: .semibold))
            }

            VStack(spacing: 4) {
                // 활성 세션
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("\(entry.summary?.activeCount ?? 0) 활성")
                        .font(.system(size: 11))
                    Spacer()
                }

                // 비용
                HStack {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(entry.summary?.formattedCost ?? "$0.00")
                        .font(.system(size: 11))
                    Spacer()
                }

                // 토큰
                HStack {
                    Image(systemName: "number.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    Text(entry.summary?.formattedTokens ?? "0")
                        .font(.system(size: 11))
                    Spacer()
                }
            }
        }
        .frame(maxWidth: 120)
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("최근 세션")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            if entry.sessions.isEmpty {
                Text("세션 없음")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(entry.sessions.prefix(2)) { session in
                    WidgetSessionRow(session: session)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget Session Row

struct WidgetSessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 6) {
            // 상태
            Circle()
                .fill(session.status.color)
                .frame(width: 6, height: 6)

            // 프로젝트
            Text(session.projectName)
                .font(.system(size: 11))
                .lineLimit(1)

            Spacer()

            // 비용
            Text(session.formattedCost)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

#Preview(as: .systemMedium) {
    AgentHubWidget()
} timeline: {
    SessionEntry(
        date: Date(),
        summary: CachedSummary(
            activeCount: 2,
            totalCount: 5,
            totalCost: 0.85,
            totalTokens: 78000,
            topSessions: [],
            lastUpdated: Date()
        ),
        sessions: [
            AgentSession(
                id: "1",
                agent: .claude,
                projectPath: "/test",
                projectName: "my-project",
                status: .running,
                tokens: TokenUsage(input: 10000, output: 2000),
                cost: 0.05
            ),
            AgentSession(
                id: "2",
                agent: .gemini,
                projectPath: "/test2",
                projectName: "other-project",
                status: .idle,
                tokens: TokenUsage(input: 5000, output: 1000),
                cost: 0.01
            )
        ]
    )
}
