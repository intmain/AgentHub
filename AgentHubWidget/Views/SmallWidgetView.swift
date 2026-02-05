import SwiftUI
import WidgetKit

/// 작은 위젯 - 활성 세션 수와 비용만 표시
struct SmallWidgetView: View {
    let entry: SessionEntry

    var body: some View {
        VStack(spacing: 8) {
            // 아이콘
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 28))
                .foregroundColor(.accentColor)

            // 활성 세션 수
            VStack(spacing: 2) {
                Text("\(entry.summary?.activeCount ?? 0)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("활성 세션")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // 비용
            if let summary = entry.summary {
                Text(summary.formattedCost)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview(as: .systemSmall) {
    AgentHubWidget()
} timeline: {
    SessionEntry(
        date: Date(),
        summary: CachedSummary(
            activeCount: 3,
            totalCount: 8,
            totalCost: 1.25,
            totalTokens: 125000,
            topSessions: [],
            lastUpdated: Date()
        ),
        sessions: []
    )
}
