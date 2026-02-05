import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var viewModel: SessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 세션 리스트
            if viewModel.filteredSessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredSessions) { session in
                            SessionRowView(session: session)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))

            Text(String(localized: "세션 없음"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Text(String(localized: "AI 에이전트 세션이 감지되면\n여기에 표시됩니다."))
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SessionListView()
        .environmentObject(SessionViewModel())
        .frame(width: 300, height: 250)
}
