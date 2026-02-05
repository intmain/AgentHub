//
//  main.swift
//  AgentHubCli
//
//  AI 코딩 에이전트 통합 모니터링 CLI
//

import Foundation

// MARK: - ANSI Colors

struct ANSIColor {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let gray = "\u{001B}[90m"
}

// MARK: - Main

func main() {
    let args = CommandLine.arguments.dropFirst()

    if args.isEmpty {
        runList(showAll: false, agentFilter: nil)
        return
    }

    let command = args.first ?? "list"

    switch command {
    case "list", "ls":
        let showAll = args.contains("--all") || args.contains("-a")
        let agentFilter = parseAgentFilter(Array(args))
        runList(showAll: showAll, agentFilter: agentFilter)

    case "watch", "w":
        let interval = parseInterval(Array(args))
        let agentFilter = parseAgentFilter(Array(args))
        runWatch(interval: interval, agentFilter: agentFilter)

    case "summary", "s":
        let jsonOutput = args.contains("--json") || args.contains("-j")
        runSummary(jsonOutput: jsonOutput)

    case "--help", "-h", "help":
        printHelp()

    case "--version", "-v":
        print("agenthub 1.0.0")

    default:
        print("Unknown command: \(command)")
        print("Run 'agenthub --help' for usage.")
        exit(1)
    }
}

// MARK: - Commands

func runList(showAll: Bool, agentFilter: String?) {
    let sessions = loadSessions()
    var filtered = showAll ? sessions : sessions.filter { $0.status.isActive }

    if let agent = agentFilter {
        filtered = filtered.filter { $0.agent.rawValue == agent }
    }

    if filtered.isEmpty {
        print("\(ANSIColor.dim)활성 세션 없음\(ANSIColor.reset)")
        return
    }

    printSessionTable(filtered)
}

func runWatch(interval: Double, agentFilter: String?) {
    print("\(ANSIColor.dim)실시간 모니터링 시작 (Ctrl+C로 종료)\(ANSIColor.reset)\n")

    signal(SIGINT) { _ in
        print("\n\(ANSIColor.dim)모니터링 종료\(ANSIColor.reset)")
        exit(0)
    }

    while true {
        // 화면 클리어
        print("\u{001B}[2J\u{001B}[H", terminator: "")

        // 헤더
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        print("\(ANSIColor.bold)AgentHub\(ANSIColor.reset) - \(formatter.string(from: Date()))\n")

        // 세션 로드 및 표시
        let sessions = loadSessions()
        var filtered = sessions.filter { $0.status.isActive }

        if let agent = agentFilter {
            filtered = filtered.filter { $0.agent.rawValue == agent }
        }

        if filtered.isEmpty {
            print("\(ANSIColor.dim)활성 세션 없음\(ANSIColor.reset)")
        } else {
            printSessionTable(filtered)
        }

        Thread.sleep(forTimeInterval: interval)
    }
}

func runSummary(jsonOutput: Bool) {
    let sessions = loadSessions()
    let activeSessions = sessions.filter { $0.status.isActive }

    if jsonOutput {
        printJSONSummary(all: sessions, active: activeSessions)
    } else {
        printTextSummary(all: sessions, active: activeSessions)
    }
}

// MARK: - Load Sessions

func loadSessions() -> [AgentSession] {
    var claudeSessions: [AgentSession] = []
    var codexSessions: [AgentSession] = []
    var geminiSessions: [AgentSession] = []

    // 병렬 처리로 세 파서 동시 실행
    let group = DispatchGroup()

    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        let parser = ClaudeLogParser()
        claudeSessions = parser.getAllSessions()
        group.leave()
    }

    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        let parser = CodexLogParser()
        codexSessions = parser.getAllSessions()
        group.leave()
    }

    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        let parser = GeminiLogParser()
        geminiSessions = parser.getAllSessions()
        group.leave()
    }

    group.wait()

    var allSessions = claudeSessions + codexSessions + geminiSessions
    return allSessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
}

// MARK: - Print Functions

func printSessionTable(_ sessions: [AgentSession]) {
    print("\(ANSIColor.bold)STATUS   AGENT    PROJECT                          TOKENS      COST       TIME\(ANSIColor.reset)")
    print("\(ANSIColor.dim)\(String(repeating: "─", count: 80))\(ANSIColor.reset)")

    for session in sessions {
        let status = "\(session.status.ansiColor)\(session.status.icon)\(ANSIColor.reset)"
        let agentName = "\(session.agent.ansiColor)\(session.agent.displayName.padding(toLength: 8, withPad: " ", startingAt: 0))\(ANSIColor.reset)"
        let projectName = String(session.projectName.prefix(32)).padding(toLength: 32, withPad: " ", startingAt: 0)
        let tokens = session.formattedTokens.padding(toLength: 11, withPad: " ", startingAt: 0)
        let cost = session.formattedCost.padding(toLength: 10, withPad: " ", startingAt: 0)
        let time = session.timeSinceLastActivity

        print("\(status)        \(agentName) \(projectName) \(tokens) \(cost) \(time)")
    }

    print("\(ANSIColor.dim)\(String(repeating: "─", count: 80))\(ANSIColor.reset)")
    let totalTokens = CostCalculator.totalTokens(sessions: sessions)
    let totalCost = CostCalculator.totalCost(sessions: sessions)
    print("\(ANSIColor.bold)Total: \(sessions.count) sessions | \(CostCalculator.formatTokens(totalTokens.total)) tokens | \(CostCalculator.formatCost(totalCost))\(ANSIColor.reset)")
}

func printTextSummary(all: [AgentSession], active: [AgentSession]) {
    let totalTokens = CostCalculator.totalTokens(sessions: active)
    let totalCost = CostCalculator.totalCost(sessions: active)

    print("\(ANSIColor.bold)═══ AgentHub Summary ═══\(ANSIColor.reset)\n")

    var agentCounts: [AgentType: Int] = [:]
    for session in active {
        agentCounts[session.agent, default: 0] += 1
    }

    print("\(ANSIColor.bold)활성 세션:\(ANSIColor.reset) \(active.count)")
    for agent in AgentType.allCases {
        let count = agentCounts[agent] ?? 0
        if count > 0 {
            print("  \(agent.ansiColor)● \(agent.displayName): \(count)\(ANSIColor.reset)")
        }
    }

    print("\n\(ANSIColor.bold)토큰 사용량:\(ANSIColor.reset)")
    print("  Input:  \(CostCalculator.formatTokens(totalTokens.input))")
    print("  Output: \(CostCalculator.formatTokens(totalTokens.output))")
    print("  Total:  \(CostCalculator.formatTokens(totalTokens.total))")

    print("\n\(ANSIColor.bold)예상 비용:\(ANSIColor.reset) \(CostCalculator.formatCost(totalCost))")
}

func printJSONSummary(all: [AgentSession], active: [AgentSession]) {
    let totalTokens = CostCalculator.totalTokens(sessions: active)
    let totalCost = CostCalculator.totalCost(sessions: active)

    var agentCounts: [String: Int] = [:]
    for session in active {
        agentCounts[session.agent.rawValue, default: 0] += 1
    }

    let summary: [String: Any] = [
        "active_sessions": active.count,
        "total_sessions": all.count,
        "agents": agentCounts,
        "tokens": [
            "input": totalTokens.input,
            "output": totalTokens.output,
            "total": totalTokens.total
        ],
        "cost": totalCost
    ]

    if let jsonData = try? JSONSerialization.data(withJSONObject: summary, options: .prettyPrinted),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        print(jsonString)
    }
}

func printHelp() {
    print("""
    \(ANSIColor.bold)AgentHub CLI\(ANSIColor.reset) - AI 코딩 에이전트 통합 모니터링

    \(ANSIColor.bold)USAGE:\(ANSIColor.reset)
        agenthub [COMMAND] [OPTIONS]

    \(ANSIColor.bold)COMMANDS:\(ANSIColor.reset)
        list, ls        세션 목록 표시 (기본)
        watch, w        실시간 모니터링
        summary, s      요약 정보
        help            도움말 표시

    \(ANSIColor.bold)OPTIONS:\(ANSIColor.reset)
        -a, --all       모든 세션 표시 (비활성 포함)
        -t, --type      에이전트 필터 (claude, codex, gemini)
        -i, --interval  갱신 간격 (초, watch 전용)
        -j, --json      JSON 형식 출력 (summary 전용)

    \(ANSIColor.bold)EXAMPLES:\(ANSIColor.reset)
        agenthub                    활성 세션 목록
        agenthub list --all         모든 세션 목록
        agenthub list -t claude     Claude 세션만
        agenthub watch -i 5         5초 간격 모니터링
        agenthub summary --json     JSON 요약
    """)
}

// MARK: - Helpers

func parseAgentFilter(_ args: [String]) -> String? {
    for (i, arg) in args.enumerated() {
        if (arg == "-t" || arg == "--type") && i + 1 < args.count {
            return args[i + 1].lowercased()
        }
    }
    return nil
}

func parseInterval(_ args: [String]) -> Double {
    for (i, arg) in args.enumerated() {
        if (arg == "-i" || arg == "--interval") && i + 1 < args.count {
            return Double(args[i + 1]) ?? 2.0
        }
    }
    return 2.0
}

// Run
main()
