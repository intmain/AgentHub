import SwiftUI
import AppKit

@main
struct AgentHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sessionViewModel = SessionViewModel()

    var body: some Scene {
        // 메뉴바 앱
        MenuBarExtra {
            MenuBarView()
                .environmentObject(sessionViewModel)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        // 대시보드 윈도우
        Window("AgentHub Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(sessionViewModel)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }

    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.hexagongrid.fill")
            if sessionViewModel.activeSessions.count > 0 {
                Text("\(sessionViewModel.activeSessions.count)")
                    .font(.system(size: 10, weight: .medium))
            }
        }
    }
}

// MARK: - Dashboard Window Controller

class DashboardWindowController {
    static let shared = DashboardWindowController()

    func openDashboard() {
        if let existingWindow = NSApp.windows.first(where: { $0.title == "AgentHub Dashboard" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            showInDock()
        } else {
            // Window scene을 통해 새 윈도우 열기
            if let url = URL(string: "agenthub://dashboard") {
                NSWorkspace.shared.open(url)
            }
            // 약간의 지연 후 Dock에 표시
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showInDock()
            }
        }
    }

    private func showInDock() {
        NSApp.unhide(nil)
        if let window = NSApp.windows.first(where: { $0.title == "AgentHub Dashboard" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 대시보드가 닫히면 Dock에서 숨김
    func hideDock() {
        // 약간의 지연 후 확인 (윈도우가 완전히 닫힌 후)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasVisibleDashboard = NSApp.windows.contains { window in
                window.isVisible && window.title == "AgentHub Dashboard"
            }

            if !hasVisibleDashboard {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
