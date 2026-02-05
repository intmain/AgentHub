import SwiftUI
import ServiceManagement

struct DashboardView: View {
    @EnvironmentObject var viewModel: SessionViewModel
    @AppStorage("showCost") private var showCost = true
    @State private var selectedSession: AgentSession?
    @State private var showSettings = false

    var body: some View {
        HSplitView {
            // 왼쪽: 세션 목록
            sessionListPanel
                .frame(minWidth: 280, maxWidth: 400)

            // 오른쪽: 상세 정보
            detailPanel
                .frame(minWidth: 400)
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            toolbarContent
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettings"))) { _ in
            selectedSession = nil
            showSettings = true
        }
    }

    // MARK: - Session List Panel

    private var sessionListPanel: some View {
        VStack(spacing: 0) {
            // 통계 헤더
            statsHeader
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 필터
            filterBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // 세션 목록
            List(viewModel.filteredSessions, selection: $selectedSession) { session in
                DashboardSessionRow(session: session, isSelected: selectedSession?.id == session.id)
                    .tag(session)
            }
            .listStyle(.inset)
            .onChange(of: selectedSession) { _, newValue in
                if newValue != nil {
                    showSettings = false
                }
            }
        }
    }

    private var statsHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Text("AgentHub")
                    .font(.title2.bold())
                Spacer()

                // 갱신 버튼
                Button {
                    viewModel.refresh()
                } label: {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
            }

            // 통계 카드
            HStack(spacing: 12) {
                DashboardStatCard(
                    title: String(localized: "활성 세션"),
                    value: "\(viewModel.activeSessions.count)",
                    subtitle: String(localized: "실행 중"),
                    icon: "bolt.fill",
                    color: .green
                )

                if showCost {
                    DashboardStatCard(
                        title: String(localized: "총 비용"),
                        value: CostCalculator.formatCost(viewModel.filteredTotalCost),
                        subtitle: String(localized: "표시된 세션"),
                        icon: "dollarsign.circle.fill",
                        color: .orange
                    )
                }

                DashboardStatCard(
                    title: String(localized: "총 토큰"),
                    value: CostCalculator.formatTokens(viewModel.filteredTotalTokens.total),
                    subtitle: String(localized: "Input + Output"),
                    icon: "number.circle.fill",
                    color: .blue
                )
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            // 에이전트 필터
            Picker(String(localized: "에이전트"), selection: $viewModel.selectedAgent) {
                Text(String(localized: "전체")).tag(nil as AgentType?)
                ForEach(AgentType.allCases) { agent in
                    HStack {
                        Circle()
                            .fill(agent.color)
                            .frame(width: 8, height: 8)
                        Text(agent.displayName)
                    }
                    .tag(agent as AgentType?)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 140)

            Spacer()

            // 마지막 갱신 (고정 너비로 레이아웃 안정화)
            if let lastUpdated = viewModel.lastUpdated {
                Text("\(String(localized: "갱신:")) \(lastUpdated, style: .relative)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(minWidth: 80, alignment: .trailing)
            }
        }
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if showSettings {
                settingsPanel
            } else if let session = selectedSession {
                SessionDetailView(session: session)
            } else {
                emptyDetailView
            }
        }
    }

    private var settingsPanel: some View {
        ScrollView {
            DashboardSettingsView()
                .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(String(localized: "세션을 선택하세요"))
                .font(.title3)
                .foregroundColor(.secondary)

            Text(String(localized: "왼쪽 목록에서 세션을 선택하면\n상세 정보가 여기에 표시됩니다."))
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // 에이전트별 뱃지 (활성 세션만)
            ForEach(AgentType.allCases) { agent in
                let count = viewModel.activeSessions.filter { $0.agent == agent }.count
                if count > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(agent.color)
                            .frame(width: 8, height: 8)
                        Text("\(count)")
                            .font(.caption.monospacedDigit())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(agent.color.opacity(0.15))
                    .cornerRadius(8)
                }
            }

            // 설정 버튼
            Button {
                selectedSession = nil
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }
}

// MARK: - Dashboard Stat Card

struct DashboardStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.title2.bold().monospacedDigit())

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Dashboard Session Row

struct DashboardSessionRow: View {
    let session: AgentSession
    let isSelected: Bool
    @AppStorage("showCost") private var showCost = true

    var body: some View {
        HStack(spacing: 12) {
            // 상태 인디케이터
            ZStack {
                Circle()
                    .fill(session.status.color.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: session.status.sfSymbol)
                    .font(.system(size: 14))
                    .foregroundColor(session.status.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.projectName)
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Text(session.timeSinceLastActivity)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    // 에이전트
                    HStack(spacing: 4) {
                        Circle()
                            .fill(session.agent.color)
                            .frame(width: 6, height: 6)
                        Text(session.agent.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // 토큰
                    Text(session.formattedTokens)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)

                    // 비용
                    if showCost {
                        Text(session.formattedCost)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    let session: AgentSession
    @EnvironmentObject var viewModel: SessionViewModel
    @AppStorage("showCost") private var showCost = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 헤더
                headerSection

                Divider()

                // 토큰 상세
                tokenSection

                Divider()

                // 시간 정보
                timeSection

                Divider()

                // 액션 버튼
                actionSection

                // 실시간 로그
                if session.logFilePath != nil {
                    Divider()
                    LogViewerView(logFilePath: session.logFilePath)
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // 에이전트 아이콘
                ZStack {
                    Circle()
                        .fill(session.agent.color.opacity(0.2))
                        .frame(width: 48, height: 48)
                    Circle()
                        .fill(session.agent.color)
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.projectName)
                        .font(.title2.bold())
                    Text(session.agent.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 상태 뱃지
                HStack(spacing: 4) {
                    Image(systemName: session.status.sfSymbol)
                    Text(statusText)
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(session.status.color.opacity(0.2))
                .foregroundColor(session.status.color)
                .cornerRadius(8)
            }

            // 프로젝트 경로
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text(session.projectPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // 모델
            if let model = session.model {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)
                    Text(model)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var statusText: String {
        switch session.status {
        case .running: return String(localized: "실행 중")
        case .waiting: return String(localized: "대기 중")
        case .completed: return String(localized: "완료")
        case .error: return String(localized: "오류")
        case .idle: return String(localized: "유휴")
        }
    }

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "토큰 사용량"))
                .font(.headline)

            HStack(spacing: 16) {
                TokenDetailCard(
                    title: "Input",
                    value: session.tokens.input,
                    color: .blue
                )
                TokenDetailCard(
                    title: "Output",
                    value: session.tokens.output,
                    color: .green
                )
                TokenDetailCard(
                    title: "Total",
                    value: session.tokens.total,
                    color: .purple
                )
            }

            if let cacheRead = session.tokens.cacheRead, cacheRead > 0 {
                HStack(spacing: 16) {
                    TokenDetailCard(
                        title: "Cache Read",
                        value: cacheRead,
                        color: .orange
                    )
                    if let cacheWrite = session.tokens.cacheWrite, cacheWrite > 0 {
                        TokenDetailCard(
                            title: "Cache Write",
                            value: cacheWrite,
                            color: .pink
                        )
                    }
                }
            }

            // 비용
            if showCost {
                HStack {
                    Text(String(localized: "예상 비용"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(session.formattedCost)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "시간 정보"))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text(String(localized: "시작"))
                        .foregroundColor(.secondary)
                    Text(session.startedAt, style: .date)
                    Text(session.startedAt, style: .time)
                }

                GridRow {
                    Text(String(localized: "마지막 활동"))
                        .foregroundColor(.secondary)
                    Text(session.lastActivityAt, style: .date)
                    Text(session.lastActivityAt, style: .time)
                }

                GridRow {
                    Text(String(localized: "지속 시간"))
                        .foregroundColor(.secondary)
                    Text(session.formattedDuration)
                        .gridCellColumns(2)
                }
            }
            .font(.system(size: 13))
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "액션"))
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    viewModel.openProjectFolder(session)
                } label: {
                    Label(String(localized: "Finder에서 열기"), systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.openInTerminal(session)
                } label: {
                    Label(String(localized: "터미널에서 열기"), systemImage: "terminal")
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.openInVSCode(session)
                } label: {
                    Label(String(localized: "VSCode에서 열기"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
    }
}

// MARK: - Token Detail Card

struct TokenDetailCard: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(CostCalculator.formatTokens(value))
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Dashboard Settings View

struct DashboardSettingsView: View {
    @EnvironmentObject var viewModel: SessionViewModel

    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("refreshInterval") private var refreshInterval = 30.0
    @AppStorage("showCost") private var showCost = true
    @AppStorage("ttsEnabled") private var ttsEnabled = false
    @AppStorage("ttsText") private var ttsText = "{agent} 작업 완료"

    private var defaultTtsText: String {
        String(localized: "{agent} 작업 완료")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 헤더
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(String(localized: "설정"))
                    .font(.title2.bold())
            }

            // 일반 설정
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "일반"))
                    .font(.headline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    Toggle(String(localized: "로그인 시 자동 시작"), isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            updateLaunchAtLogin(newValue)
                        }

                    HStack {
                        Text(String(localized: "갱신 주기"))
                        Spacer()
                        Picker("", selection: $refreshInterval) {
                            Text(String(localized: "15초")).tag(15.0)
                            Text(String(localized: "30초")).tag(30.0)
                            Text(String(localized: "1분")).tag(60.0)
                            Text(String(localized: "5분")).tag(300.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }

                    Toggle(String(localized: "비용 정보 표시"), isOn: $showCost)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // 알림 설정
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "알림"))
                    .font(.headline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    Toggle(String(localized: "음성 알림 (TTS)"), isOn: $ttsEnabled)

                    if ttsEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "음성 텍스트"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField(String(localized: "예: {agent} 작업 완료"), text: $ttsText)
                                .textFieldStyle(.roundedBorder)
                            Text(String(localized: "사용 가능: {agent}, {project}"))
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Button(String(localized: "테스트")) {
                                NotificationManager.shared.speak(text:
                                    ttsText
                                        .replacingOccurrences(of: "{agent}", with: "Claude")
                                        .replacingOccurrences(of: "{project}", with: String(localized: "테스트 프로젝트"))
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.leading, 20)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // 에이전트 경로
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "에이전트 로그 경로"))
                    .font(.headline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    ForEach([AgentType.claude, .codex, .gemini], id: \.self) { agent in
                        HStack {
                            Circle()
                                .fill(agent.color)
                                .frame(width: 8, height: 8)
                            Text(agent.displayName)
                                .frame(width: 60, alignment: .leading)
                            Text(agent.logPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if FileManager.default.fileExists(atPath: agent.logPath) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 12))
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // 데이터
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "데이터"))
                    .font(.headline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text(String(localized: "마지막 갱신"))
                        Spacer()
                        if let lastUpdated = viewModel.lastUpdated {
                            Text(lastUpdated, style: .relative)
                                .foregroundColor(.secondary)
                        } else {
                            Text("-")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text(String(localized: "활성 세션 수"))
                        Spacer()
                        Text("\(viewModel.activeSessions.count)")
                            .foregroundColor(.secondary)
                    }

                    Button(String(localized: "지금 새로고침")) {
                        viewModel.refresh()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // CLI 설치
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "명령줄 도구"))
                    .font(.headline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("agenthub CLI")
                                .font(.system(size: 13, weight: .medium))
                            Text(String(localized: "터미널에서 세션 모니터링"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if CliInstaller.isInstalled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(String(localized: "설치됨"))
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    Divider()

                    if CliInstaller.isInstalled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "사용법:"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(localized: "agenthub          # 세션 목록\nagenthub watch    # 실시간 모니터링\nagenthub summary  # 요약"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)

                            Button(String(localized: "CLI 제거")) {
                                CliInstaller.uninstall()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        Button(String(localized: "CLI 설치")) {
                            CliInstaller.install()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // 정보
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "정보"))
                    .font(.headline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text(String(localized: "버전"))
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // 앱 종료
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                    Text(String(localized: "앱 종료"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)

            Spacer()
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
    }
}

// MARK: - Log Viewer

class LogViewerViewModel: ObservableObject {
    @Published var logLines: [LogLine] = []
    @Published var isWatching = false

    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var logFilePath: String?
    private let maxLines = 100

    struct LogLine: Identifiable {
        let id = UUID()
        let text: String
        let type: LineType
        let timestamp: Date

        enum LineType {
            case assistant
            case user
            case system
            case tool
        }
    }

    func startWatching(path: String?) {
        stopWatching()

        guard let path = path else { return }
        logFilePath = path

        // 초기 로드 (마지막 50줄)
        loadInitialContent(path: path)

        // 파일 감시 시작
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        fileHandle = handle
        handle.seekToEndOfFile()

        let descriptor = handle.fileDescriptor
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            self?.readNewContent()
        }

        source?.setCancelHandler { [weak self] in
            self?.fileHandle?.closeFile()
            self?.fileHandle = nil
        }

        source?.resume()
        isWatching = true
    }

    func stopWatching() {
        source?.cancel()
        source = nil
        fileHandle?.closeFile()
        fileHandle = nil
        isWatching = false
    }

    private func loadInitialContent(path: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
            .suffix(50)
            .filter { !$0.isEmpty }

        DispatchQueue.main.async {
            self.logLines = lines.compactMap { self.parseLine($0) }
        }
    }

    private func readNewContent() {
        guard let handle = fileHandle else { return }

        let data = handle.availableData
        guard !data.isEmpty,
              let newContent = String(data: data, encoding: .utf8) else { return }

        let newLines = newContent.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { parseLine($0) }

        DispatchQueue.main.async {
            self.logLines.append(contentsOf: newLines)
            if self.logLines.count > self.maxLines {
                self.logLines.removeFirst(self.logLines.count - self.maxLines)
            }
        }
    }

    private func parseLine(_ line: String) -> LogLine? {
        // JSONL 파싱 시도
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LogLine(text: line, type: .system, timestamp: Date())
        }

        // 메시지 타입 확인
        let role = (json["message"] as? [String: Any])?["role"] as? String
        let type: LogLine.LineType
        var displayText = ""

        switch role {
        case "assistant":
            type = .assistant
            if let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String {
                        displayText += text
                    } else if block["type"] as? String == "tool_use" {
                        let toolName = block["name"] as? String ?? "tool"
                        displayText += "[Tool: \(toolName)]"
                    }
                }
            }
        case "user":
            type = .user
            if let content = (json["message"] as? [String: Any])?["content"] as? String {
                displayText = content
            } else if let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String {
                        displayText += text
                    }
                }
            }
        default:
            type = .system
            if let eventType = json["type"] as? String {
                displayText = "[\(eventType)]"
            }
        }

        guard !displayText.isEmpty else { return nil }

        return LogLine(
            text: String(displayText.prefix(500)),
            type: type,
            timestamp: Date()
        )
    }

    deinit {
        stopWatching()
    }
}

struct LogViewerView: View {
    let logFilePath: String?
    @StateObject private var viewModel = LogViewerViewModel()
    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 헤더
            HStack {
                Text(String(localized: "실시간 로그"))
                    .font(.headline)

                Spacer()

                if viewModel.isWatching {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(String(localized: "실시간"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(String(localized: "자동 스크롤"), isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }

            // 로그 내용
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.logLines) { line in
                            LogLineView(line: line)
                                .id(line.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: viewModel.logLines.count) { _, _ in
                    if autoScroll, let lastLine = viewModel.logLines.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastLine.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .frame(minHeight: 150, maxHeight: 300)
        }
        .onAppear {
            viewModel.startWatching(path: logFilePath)
        }
        .onDisappear {
            viewModel.stopWatching()
        }
        .onChange(of: logFilePath) { _, newPath in
            viewModel.startWatching(path: newPath)
        }
    }
}

struct LogLineView: View {
    let line: LogViewerViewModel.LogLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 아이콘
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .frame(width: 16)

            // 텍스트
            Text(line.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(textColor)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch line.type {
        case .assistant: return "sparkles"
        case .user: return "person.fill"
        case .system: return "gearshape"
        case .tool: return "wrench.fill"
        }
    }

    private var iconColor: Color {
        switch line.type {
        case .assistant: return .purple
        case .user: return .blue
        case .system: return .gray
        case .tool: return .orange
        }
    }

    private var textColor: Color {
        switch line.type {
        case .assistant: return .primary
        case .user: return .blue
        case .system: return .secondary
        case .tool: return .orange
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(SessionViewModel())
        .frame(width: 900, height: 600)
}
