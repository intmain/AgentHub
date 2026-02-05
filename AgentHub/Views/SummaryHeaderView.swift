import SwiftUI

struct SummaryHeaderView: View {
    @EnvironmentObject var viewModel: SessionViewModel
    @AppStorage("showCost") private var showCost = true

    var body: some View {
        VStack(spacing: 12) {
            // 타이틀
            HStack {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("AgentHub")
                    .font(.headline)
                Spacer()
            }

            // 통계 카드
            HStack(spacing: 16) {
                StatCard(
                    title: String(localized: "활성"),
                    value: "\(viewModel.activeSessions.count)",
                    icon: "bolt.fill",
                    color: .green
                )

                if showCost {
                    StatCard(
                        title: String(localized: "비용"),
                        value: CostCalculator.formatCost(viewModel.filteredTotalCost),
                        icon: "dollarsign.circle.fill",
                        color: .orange
                    )
                }

                StatCard(
                    title: String(localized: "토큰"),
                    value: CostCalculator.formatTokens(viewModel.filteredTotalTokens.total),
                    icon: "number.circle.fill",
                    color: .blue
                )
            }

            // 에이전트별 요약
            HStack(spacing: 8) {
                ForEach(AgentType.allCases) { agent in
                    let count = viewModel.agentCounts[agent] ?? 0
                    if count > 0 {
                        AgentBadge(agent: agent, count: count)
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()

            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Agent Badge

struct AgentBadge: View {
    let agent: AgentType
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(agent.color)
                .frame(width: 8, height: 8)

            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(agent.color.opacity(0.15))
        .cornerRadius(10)
    }
}

#Preview {
    SummaryHeaderView()
        .environmentObject(SessionViewModel())
        .padding()
        .frame(width: 300)
}
