import Foundation
import Combine
import SwiftUI
import UserNotifications
import WidgetKit
import AVFoundation

// MARK: - Notification Manager

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    // TTS
    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        checkAuthorization()
    }

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    /// TTS로 텍스트 읽기
    func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    /// TTS 텍스트 생성 (플레이스홀더 치환)
    private func buildTTSText(template: String, projectName: String, agent: AgentType) -> String {
        var text = template
        text = text.replacingOccurrences(of: "{project}", with: projectName)
        text = text.replacingOccurrences(of: "{agent}", with: agent.displayName)
        return text
    }

    /// 세션이 대기 상태로 전환되었을 때 알림
    func notifySessionWaiting(projectName: String, agent: AgentType) {
        print("notifySessionWaiting called - isAuthorized: \(isAuthorized)")

        // TTS 설정 확인
        let ttsEnabled = UserDefaults.standard.bool(forKey: "ttsEnabled")
        let defaultTtsText = String(localized: "{agent} 작업 완료")
        let ttsText = UserDefaults.standard.string(forKey: "ttsText") ?? defaultTtsText

        if ttsEnabled {
            let spokenText = buildTTSText(template: ttsText, projectName: projectName, agent: agent)
            speak(text: spokenText)
        }

        // 권한 상태 다시 확인
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("Notification settings: \(settings.authorizationStatus.rawValue)")

            guard settings.authorizationStatus == .authorized else {
                print("Notifications not authorized")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "\(agent.displayName) \(String(localized: "준비 완료"))"
            content.body = "\(projectName) - \(String(localized: "작업 완료"))"
            content.sound = ttsEnabled ? nil : .default  // TTS 사용 시 사운드 끔

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Notification error: \(error)")
                } else {
                    print("Notification sent successfully!")
                }
            }
        }
    }

    /// 세션이 완료되었을 때 알림
    func notifySessionCompleted(projectName: String, agent: AgentType) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(agent.displayName) \(String(localized: "완료"))"
        content.body = "\(projectName) \(String(localized: "세션이 종료되었습니다"))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Session View Model

@MainActor
class SessionViewModel: ObservableObject {
    // 세션 데이터
    @Published var sessions: [AgentSession] = []
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?

    // 이전 상태 추적 (알림용)
    private var previousSessionStates: [String: SessionStatus] = [:]

    // 필터
    @Published var selectedAgent: AgentType?

    // 파서 (nonisolated로 백그라운드에서 접근 가능)
    private nonisolated let claudeParser = ClaudeLogParser()
    private nonisolated let codexParser = CodexLogParser()
    private nonisolated let geminiParser = GeminiLogParser()

    // 파일 감시
    private var fileWatcher: FileWatcher?
    private var signalWatcher: FileWatcher?  // Stop hook 신호 파일 감시
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Debounce 관련
    private var debounceWorkItem: DispatchWorkItem?
    private var isRefreshing = false
    private var pendingRefresh = false

    // 설정
    var refreshInterval: TimeInterval = 30.0
    private let debounceDelay: TimeInterval = 2.0  // 파일 변경 후 2초 대기

    // 신호 파일 경로
    private let signalDir = "/tmp/agenthub-signals"
    private let signalFile = "/tmp/agenthub-signals/stop-signal"

    init() {
        setupSignalDirectory()
        setupFileWatcher()
        setupSignalWatcher()
        startRefreshTimer()
        refresh()
    }

    deinit {
        refreshTimer?.invalidate()
        fileWatcher?.stop()
        signalWatcher?.stop()
        debounceWorkItem?.cancel()
    }

    // MARK: - Computed Properties

    var activeSessions: [AgentSession] {
        sessions.filter { $0.status.isActive }
    }

    var filteredSessions: [AgentSession] {
        var result = activeSessions  // 항상 활성 세션만

        if let agent = selectedAgent {
            result = result.filter { $0.agent == agent }
        }

        return result
    }

    var totalCost: Double {
        CostCalculator.totalCost(sessions: sessions)
    }

    var totalTokens: TokenUsage {
        CostCalculator.totalTokens(sessions: sessions)
    }

    /// 필터링된 세션의 비용 합계 (화면에 표시되는 세션 기준)
    var filteredTotalCost: Double {
        CostCalculator.totalCost(sessions: filteredSessions)
    }

    /// 필터링된 세션의 토큰 합계 (화면에 표시되는 세션 기준)
    var filteredTotalTokens: TokenUsage {
        CostCalculator.totalTokens(sessions: filteredSessions)
    }

    var agentCounts: [AgentType: Int] {
        var counts: [AgentType: Int] = [:]
        for agent in AgentType.allCases {
            counts[agent] = activeSessions.filter { $0.agent == agent }.count
        }
        return counts
    }

    // MARK: - Actions

    /// 수동 새로고침 (즉시 실행)
    func refresh() {
        performRefresh()
    }

    /// 실제 새로고침 수행
    private func performRefresh() {
        // 이미 새로고침 중이면 대기열에 추가
        guard !isRefreshing else {
            pendingRefresh = true
            return
        }

        isRefreshing = true
        isLoading = true
        errorMessage = nil

        // 백그라운드에서 파싱 수행
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let allSessions = await self.loadSessionsInBackground()

            // 메인 스레드에서 UI 업데이트
            await MainActor.run {
                // 상태 변화 감지 및 알림
                self.detectStateChangesAndNotify(newSessions: allSessions)

                self.sessions = allSessions
                self.lastUpdated = Date()
                self.isLoading = false
                self.isRefreshing = false

                // 대기 중인 새로고침이 있으면 실행
                if self.pendingRefresh {
                    self.pendingRefresh = false
                    // 약간의 딜레이 후 실행
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5초
                        self.performRefresh()
                    }
                }
            }

            // 백그라운드에서 캐시 저장
            await self.saveCacheInBackground(sessions: allSessions)
        }
    }

    /// 백그라운드에서 세션 로드 (nonisolated)
    private nonisolated func loadSessionsInBackground() async -> [AgentSession] {
        var allSessions: [AgentSession] = []

        // Claude 세션
        let claudeSessions = claudeParser.getAllSessions()
        allSessions.append(contentsOf: claudeSessions)

        // Codex 세션
        let codexSessions = codexParser.getAllSessions()
        allSessions.append(contentsOf: codexSessions)

        // Gemini 세션
        let geminiSessions = geminiParser.getAllSessions()
        allSessions.append(contentsOf: geminiSessions)

        // 최근 활동 순 정렬
        allSessions.sort { $0.lastActivityAt > $1.lastActivityAt }

        return allSessions
    }

    /// 백그라운드에서 캐시 저장 및 위젯 갱신
    private nonisolated func saveCacheInBackground(sessions: [AgentSession]) async {
        SessionCache.shared.save(sessions: sessions)

        // 위젯 갱신 트리거
        await MainActor.run {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func openProjectFolder(_ session: AgentSession) {
        let url = URL(fileURLWithPath: session.projectPath)
        NSWorkspace.shared.open(url)
    }

    func openInTerminal(_ session: AgentSession) {
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(session.projectPath)'"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    func openInVSCode(_ session: AgentSession) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["code", "-r", session.projectPath]  // -r: reuse window
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            // code 명령어가 없으면 open으로 시도
            let openTask = Process()
            openTask.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            openTask.arguments = ["-a", "Visual Studio Code", session.projectPath]
            try? openTask.run()
        }
    }

    // MARK: - Private

    /// 신호 디렉토리 생성
    private func setupSignalDirectory() {
        try? FileManager.default.createDirectory(
            atPath: signalDir,
            withIntermediateDirectories: true
        )
    }

    /// Stop hook 신호 파일 감시
    private func setupSignalWatcher() {
        // 신호 디렉토리 감시
        signalWatcher = FileWatcher(paths: [signalDir]) { [weak self] in
            self?.handleStopSignal()
        }
        signalWatcher?.start()
    }

    /// Stop 신호 처리 - 즉시 알림 전송
    private func handleStopSignal() {
        guard FileManager.default.fileExists(atPath: signalFile) else { return }

        // 신호 파일 읽기
        guard let data = FileManager.default.contents(atPath: signalFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // 프로젝트 정보 추출
        let projectPath = json["project"] as? String ?? ""
        let projectName = (projectPath as NSString).lastPathComponent

        // 즉시 알림 전송
        Task { @MainActor in
            NotificationManager.shared.notifySessionWaiting(
                projectName: projectName.isEmpty ? "Claude" : projectName,
                agent: .claude
            )
        }

        // 신호 파일 삭제 (중복 알림 방지)
        try? FileManager.default.removeItem(atPath: signalFile)

        // 세션 목록 새로고침
        Task { @MainActor in
            self.performRefresh()
        }
    }

    private func setupFileWatcher() {
        var paths: [String] = []

        for agent in [AgentType.claude, .codex, .gemini] {
            let path = agent.logPath
            if FileManager.default.fileExists(atPath: path) {
                paths.append(path)
            }
        }

        guard !paths.isEmpty else { return }

        fileWatcher = FileWatcher(paths: paths) { [weak self] in
            self?.scheduleDebounceRefresh()
        }
        fileWatcher?.start()
    }

    /// Debounce된 새로고침 스케줄
    private func scheduleDebounceRefresh() {
        // 기존 대기 중인 작업 취소
        debounceWorkItem?.cancel()

        // 새 작업 생성
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.performRefresh()
            }
        }

        debounceWorkItem = workItem

        // debounceDelay 후에 실행
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performRefresh()
            }
        }
    }

    // MARK: - State Change Detection

    /// 상태 변화를 감지하고 알림 전송
    /// Note: waiting 알림은 Stop hook을 통해서만 전송 (중복 방지)
    private func detectStateChangesAndNotify(newSessions: [AgentSession]) {
        for session in newSessions {
            let previousStatus = previousSessionStates[session.id]

            // 디버그: 상태 변화 출력
            if let prev = previousStatus, prev != session.status {
                print("[\(session.projectName)] 상태 변화: \(prev) → \(session.status)")
            }

            // running → completed 전환 감지 (세션 종료)
            // Note: waiting 알림은 Stop hook에서 처리하므로 여기서는 completed만 처리
            if previousStatus == .running && session.status == .completed {
                print("🔔 알림 전송: \(session.projectName) - completed")
                NotificationManager.shared.notifySessionCompleted(
                    projectName: session.projectName,
                    agent: session.agent
                )
            }

            // 현재 상태 저장
            previousSessionStates[session.id] = session.status
        }
    }
}
