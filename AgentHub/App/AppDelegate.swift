import AppKit
import ServiceManagement
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemMenu: NSMenu?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 시작 시 Dock에서 숨김 (메뉴바만 표시)
        NSApp.setActivationPolicy(.accessory)

        // 로그인 시 자동 시작 설정 확인
        checkLaunchAtLogin()

        // 알림 권한 요청
        requestNotificationPermission()

        // 오른쪽 클릭 메뉴 설정
        setupRightClickMenu()

        // 윈도우 닫힘 감지
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.title == "AgentHub Dashboard" else { return }

        // Dock에서 숨김 (hideDock 내부에서 지연 처리)
        DashboardWindowController.shared.hideDock()
    }

    // MARK: - Right Click Menu

    private func setupRightClickMenu() {
        // 컨텍스트 메뉴 생성
        statusItemMenu = NSMenu()
        statusItemMenu?.addItem(NSMenuItem(title: NSLocalizedString("대시보드 열기", comment: ""), action: #selector(openDashboard), keyEquivalent: "d"))
        statusItemMenu?.addItem(NSMenuItem.separator())
        statusItemMenu?.addItem(NSMenuItem(title: NSLocalizedString("앱 종료", comment: ""), action: #selector(quitApp), keyEquivalent: "q"))

        // 오른쪽 클릭 이벤트 모니터링
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
            // 상태바 영역에서 오른쪽 클릭인지 확인
            if let statusItem = NSApp.windows.first(where: { $0.className.contains("NSStatusBarWindow") }),
               statusItem.frame.contains(NSEvent.mouseLocation) {
                self?.showContextMenu()
                return nil
            }
            return event
        }
    }

    private func showContextMenu() {
        guard let menu = statusItemMenu else { return }
        // 마우스 위치에 메뉴 표시
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func openDashboard() {
        DashboardWindowController.shared.openDashboard()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            }
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 정리 작업
    }

    /// 마지막 윈도우를 닫아도 앱 종료하지 않음 (메뉴바 유지)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Launch at Login

    private func checkLaunchAtLogin() {
        // macOS 13+ 에서는 SMAppService 사용
        if #available(macOS 13.0, *) {
            // 설정에서 자동 시작 여부 확인
            let enabled = UserDefaults.standard.bool(forKey: "launchAtLogin")
            setLaunchAtLogin(enabled: enabled)
        }
    }

    @available(macOS 13.0, *)
    func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}
