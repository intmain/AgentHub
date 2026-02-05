import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var viewModel: SessionViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            SummaryHeaderView()

            Divider()
                .padding(.vertical, 8)

            // 세션 목록
            SessionListView()

            Divider()
                .padding(.vertical, 8)

            // 하단 버튼
            bottomButtons
        }
        .padding()
        .frame(width: 320, height: 400)
    }

    private var bottomButtons: some View {
        VStack(spacing: 8) {
            // 대시보드 열기 버튼
            Button {
                openWindow(id: "dashboard")

                // 약간의 지연 후 Dock에 표시
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.unhide(nil)
                    if let window = NSApp.windows.first(where: { $0.title == "AgentHub Dashboard" }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                HStack {
                    Image(systemName: "rectangle.expand.vertical")
                    Text(String(localized: "대시보드 열기"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            // 기타 버튼들
            HStack {
                Button {
                    viewModel.refresh()
                } label: {
                    HStack(spacing: 4) {
                        Group {
                            if viewModel.isLoading {
                                ProgressView()
                                    .scaleEffect(0.5)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                        }
                        .frame(width: 14, height: 14)

                        Text(String(localized: "새로고침"))
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                if let lastUpdated = viewModel.lastUpdated {
                    Text(formatLastUpdated(lastUpdated))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    // 대시보드 열고 설정 화면으로 이동
                    openWindow(id: "dashboard")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.unhide(nil)
                        if let window = NSApp.windows.first(where: { $0.title == "AgentHub Dashboard" }) {
                            window.makeKeyAndOrderFront(nil)
                        }
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        // 설정 화면 열기 알림
                        NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        Text(String(localized: "설정"))
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }

    private func formatLastUpdated(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return String(localized: "방금 갱신")
        } else {
            let minutes = Int(interval / 60)
            return String(format: String(localized: "%d분 전"), minutes)
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(SessionViewModel())
}
