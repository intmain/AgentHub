import SwiftUI

struct SessionRowView: View {
    @EnvironmentObject var viewModel: SessionViewModel
    @AppStorage("showCost") private var showCost = true
    let session: AgentSession

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // 상태 인디케이터
            statusIndicator

            // 세션 정보
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.projectName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    Text(session.timeSinceLastActivity)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                HStack {
                    // 에이전트 배지
                    HStack(spacing: 3) {
                        Circle()
                            .fill(session.agent.color)
                            .frame(width: 6, height: 6)
                        Text(session.agent.displayName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))

                    // 토큰
                    Text(session.formattedTokens)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(.secondary)

                    if showCost {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))

                        // 비용
                        Text(session.formattedCost)
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(.orange)
                    }
                }
            }

            // 액션 버튼 (호버 시)
            if isHovered {
                HStack(spacing: 4) {
                    actionButton(icon: "folder", tooltip: String(localized: "Finder에서 열기")) {
                        viewModel.openProjectFolder(session)
                    }

                    actionButton(icon: "terminal", tooltip: String(localized: "터미널에서 열기")) {
                        viewModel.openInTerminal(session)
                    }

                    actionButton(icon: "chevron.left.forwardslash.chevron.right", tooltip: String(localized: "VSCode에서 열기")) {
                        viewModel.openInVSCode(session)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(session.status.color.opacity(0.2))
                .frame(width: 28, height: 28)

            Image(systemName: session.status.sfSymbol)
                .font(.system(size: 12))
                .foregroundColor(session.status.color)

            // 실행 중일 때 펄스 애니메이션
            if session.status == .running {
                Circle()
                    .stroke(session.status.color, lineWidth: 1)
                    .frame(width: 28, height: 28)
                    .opacity(0.5)
            }
        }
    }

    private func actionButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.08))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

#Preview {
    VStack {
        SessionRowView(session: AgentSession(
            id: "test-1",
            agent: .claude,
            projectPath: "/Users/test/project",
            projectName: "my-project",
            status: .running,
            tokens: TokenUsage(input: 15000, output: 3000),
            cost: 0.075,
            startedAt: Date().addingTimeInterval(-3600),
            lastActivityAt: Date().addingTimeInterval(-30)
        ))

        SessionRowView(session: AgentSession(
            id: "test-2",
            agent: .gemini,
            projectPath: "/Users/test/another",
            projectName: "another-project",
            status: .idle,
            tokens: TokenUsage(input: 5000, output: 1000),
            cost: 0.012,
            startedAt: Date().addingTimeInterval(-7200),
            lastActivityAt: Date().addingTimeInterval(-1800)
        ))
    }
    .environmentObject(SessionViewModel())
    .padding()
    .frame(width: 300)
}
