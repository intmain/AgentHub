import Foundation

/// Codex CLI 로그 파서
/// Codex는 ~/.codex/sessions/YYYY/MM/DD/ 에 JSONL 형식으로 세션 저장
public class CodexLogParser {
    private let basePath: String

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.basePath = "\(home)/.codex/sessions"
    }

    /// 세션 메타 정보
    private struct SessionMeta: Decodable {
        let timestamp: String?
        let type: String?
        let payload: Payload?

        struct Payload: Decodable {
            let id: String?
            let cwd: String?
            let cli_version: String?
            let model_provider: String?
        }
    }

    /// 이벤트 메시지 (토큰 사용량 포함)
    private struct EventMessage: Decodable {
        let timestamp: String?
        let type: String?
        let payload: Payload?

        struct Payload: Decodable {
            let type: String?  // "token_count"
            let info: TokenInfo?
        }

        struct TokenInfo: Decodable {
            let total_token_usage: TokenUsageDetail?
        }

        struct TokenUsageDetail: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cached_input_tokens: Int?
            let total_tokens: Int?
        }
    }

    /// 실행 중인 Codex 프로세스의 작업 디렉토리 가져오기 (최적화: pgrep + lsof 한번에)
    private func getRunningCodexWorkingDirs() -> Set<String> {
        var dirs = Set<String>()

        // 1. pgrep -x 로 정확한 이름 매칭
        let pgrepTask = Process()
        pgrepTask.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrepTask.arguments = ["-x", "codex"]

        let pgrepPipe = Pipe()
        pgrepTask.standardOutput = pgrepPipe
        pgrepTask.standardError = FileHandle.nullDevice

        do {
            try pgrepTask.run()
            pgrepTask.waitUntilExit()

            let pgrepData = pgrepPipe.fileHandleForReading.readDataToEndOfFile()
            let pgrepOutput = String(data: pgrepData, encoding: .utf8) ?? ""
            let pids = pgrepOutput.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard !pids.isEmpty else { return dirs }

            // 2. lsof로 모든 PID의 cwd를 한번에 가져오기
            let pidList = pids.joined(separator: ",")
            let lsofTask = Process()
            lsofTask.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            lsofTask.arguments = ["-a", "-d", "cwd", "-Fn", "-p", pidList]

            let lsofPipe = Pipe()
            lsofTask.standardOutput = lsofPipe
            lsofTask.standardError = FileHandle.nullDevice

            try lsofTask.run()
            lsofTask.waitUntilExit()

            let lsofData = lsofPipe.fileHandleForReading.readDataToEndOfFile()
            let lsofOutput = String(data: lsofData, encoding: .utf8) ?? ""

            for line in lsofOutput.components(separatedBy: .newlines) {
                if line.hasPrefix("n/") {
                    let cwd = String(line.dropFirst())
                    dirs.insert(cwd)
                }
            }
        } catch {
            // 실패 시 빈 세트 반환
        }

        return dirs
    }

    /// 모든 JSONL 세션 파일 찾기
    private func findAllSessionFiles() -> [(path: String, mtime: Date)] {
        var files: [(path: String, mtime: Date)] = []
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: basePath) else { return files }

        // 재귀적으로 .jsonl 파일 찾기
        if let enumerator = fileManager.enumerator(atPath: basePath) {
            while let element = enumerator.nextObject() as? String {
                if element.hasSuffix(".jsonl") {
                    let fullPath = "\(basePath)/\(element)"
                    if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                       let mtime = attrs[.modificationDate] as? Date {
                        files.append((fullPath, mtime))
                    }
                }
            }
        }

        // 최신순 정렬
        files.sort { $0.mtime > $1.mtime }
        return files
    }

    /// 세션 파일 파싱
    private func parseSessionFile(_ filePath: String, mtime: Date, runningDirs: Set<String>) -> AgentSession? {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        let decoder = JSONDecoder()

        var sessionId: String?
        var cwd: String?
        var cliVersion: String?
        var startTime: Date?
        var lastTime: Date?
        var totalInputTokens = 0
        var totalOutputTokens = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8) else { continue }

            // session_meta 파싱
            if let meta = try? decoder.decode(SessionMeta.self, from: data),
               meta.type == "session_meta" {
                sessionId = meta.payload?.id
                cwd = meta.payload?.cwd
                cliVersion = meta.payload?.cli_version
                if let ts = meta.timestamp {
                    startTime = parseTimestamp(ts)
                }
            }

            // 토큰 사용량 파싱 (event_msg 타입에서 token_count 정보 추출)
            if let event = try? decoder.decode(EventMessage.self, from: data) {
                if event.type == "event_msg",
                   event.payload?.type == "token_count",
                   let usage = event.payload?.info?.total_token_usage {
                    // 마지막 total_token_usage 값 사용 (누적값이므로)
                    totalInputTokens = usage.input_tokens ?? totalInputTokens
                    totalOutputTokens = usage.output_tokens ?? totalOutputTokens
                }
                if let ts = event.timestamp, let time = parseTimestamp(ts) {
                    if lastTime == nil || time > lastTime! {
                        lastTime = time
                    }
                }
            }
        }

        guard let id = sessionId, let projectPath = cwd else {
            return nil
        }

        let projectName = (projectPath as NSString).lastPathComponent
        let actualStartTime = startTime ?? mtime
        let actualLastTime = lastTime ?? mtime

        // 상태 결정 - 프로세스 확인
        let isRunning = runningDirs.contains { dir in
            dir == projectPath ||
            dir.hasPrefix(projectPath + "/") ||
            projectPath.hasPrefix(dir + "/")
        }

        let idleSeconds = Date().timeIntervalSince(actualLastTime)
        let status: SessionStatus
        if isRunning {
            status = idleSeconds < 5 ? .running : .waiting  // 5초로 변경
        } else {
            status = .completed
        }

        let tokens = TokenUsage(
            input: totalInputTokens,
            output: totalOutputTokens
        )
        let cost = CostCalculator.calculate(agent: .codex, tokens: tokens)

        return AgentSession(
            id: id,
            agent: .codex,
            projectPath: projectPath,
            projectName: projectName,
            status: status,
            tokens: tokens,
            cost: cost,
            startedAt: actualStartTime,
            lastActivityAt: actualLastTime,
            duration: actualLastTime.timeIntervalSince(actualStartTime),
            model: cliVersion,
            logFilePath: filePath
        )
    }

    /// 타임스탬프 파싱 (ISO8601)
    private func parseTimestamp(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    /// 모든 세션 가져오기 (활성 프로세스만)
    public func getAllSessions(maxAgeDays: Int = 7) -> [AgentSession] {
        let runningDirs = getRunningCodexWorkingDirs()

        // 실행 중인 프로세스가 없으면 빈 배열 반환
        if runningDirs.isEmpty {
            return []
        }

        let sessionFiles = findAllSessionFiles()

        var sessions: [AgentSession] = []
        var seenProjects = Set<String>()  // 프로젝트당 최신 세션만

        for file in sessionFiles {
            if let session = parseSessionFile(file.path, mtime: file.mtime, runningDirs: runningDirs) {
                // 활성 세션만 (프로젝트당 최신 세션)
                if session.status.isActive && !seenProjects.contains(session.projectPath) {
                    sessions.append(session)
                    seenProjects.insert(session.projectPath)
                }
            }
        }

        return sessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// 활성 세션만 가져오기
    public func getActiveSessions() -> [AgentSession] {
        getAllSessions(maxAgeDays: 365).filter { $0.status.isActive }
    }
}
