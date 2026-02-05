import Foundation

/// Claude Code 로그 파서
/// 참고: https://github.com/ryoppippi/ccusage
///
/// Claude Code는 ~/.claude/projects/{project-hash}/에 JSONL 형식으로 로그 저장
public class ClaudeLogParser {
    private let basePath: String

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.basePath = "\(home)/.claude/projects"
    }

    /// 실행 중인 Claude CLI 프로세스들의 작업 디렉토리 가져오기 (최적화: pgrep + lsof 한번에)
    private func getRunningClaudeWorkingDirs() -> [String: [Int]] {
        var cwdToPids: [String: [Int]] = [:]

        // 1. pgrep으로 claude PID 목록 가져오기
        let pgrepTask = Process()
        pgrepTask.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrepTask.arguments = ["-x", "claude"]

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

            guard !pids.isEmpty else { return cwdToPids }

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

            // 출력 형식: p<pid>\nfcwd\nn<path>\np<pid>\nfcwd\nn<path>...
            var currentPid: Int?
            for line in lsofOutput.components(separatedBy: .newlines) {
                if line.hasPrefix("p") {
                    currentPid = Int(String(line.dropFirst()))
                } else if line.hasPrefix("n/"), let pid = currentPid {
                    let cwd = String(line.dropFirst())
                    cwdToPids[cwd, default: []].append(pid)
                }
            }
        } catch {
            // 프로세스 확인 실패 시 빈 딕셔너리 반환
        }

        return cwdToPids
    }

    /// 프로젝트 경로에서 실행 중인 프로세스 수 확인
    private func countRunningProcesses(_ projectPath: String, runningDirs: [String: [Int]]) -> Int {
        var count = 0
        for (cwd, pids) in runningDirs {
            // 정확히 일치하거나 하위 디렉토리 관계
            if cwd == projectPath ||
               cwd.hasPrefix(projectPath + "/") ||
               projectPath.hasPrefix(cwd + "/") {
                count += pids.count
            }
        }
        return count
    }

    /// Claude 로그 엔트리 구조
    private struct LogEntry: Decodable {
        let type: String?
        let timestamp: String?
        let message: Message?
        let sessionId: String?
        let conversationId: String?

        struct Message: Decodable {
            let role: String?
            let model: String?
            let usage: Usage?
        }

        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
    }

    /// 프로젝트 매핑 정보
    public struct ProjectMapping {
        public let hash: String
        public let path: String
        public let name: String
    }

    /// sessions-index.json 구조
    private struct SessionsIndex: Decodable {
        let originalPath: String?
    }

    /// 모든 프로젝트 디렉토리 탐색
    public func getProjects() -> [ProjectMapping] {
        var projects: [ProjectMapping] = []
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: basePath) else { return projects }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: basePath)

            for dirName in contents {
                let projectDir = "\(basePath)/\(dirName)"
                var isDirectory: ObjCBool = false

                guard fileManager.fileExists(atPath: projectDir, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                var projectPath = projectDir
                var projectName = dirName

                // sessions-index.json에서 originalPath 읽기
                let indexFile = "\(projectDir)/sessions-index.json"
                if fileManager.fileExists(atPath: indexFile),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: indexFile)),
                   let index = try? JSONDecoder().decode(SessionsIndex.self, from: data),
                   let origPath = index.originalPath {
                    projectPath = origPath
                    projectName = (origPath as NSString).lastPathComponent
                }

                projects.append(ProjectMapping(
                    hash: dirName,
                    path: projectPath,
                    name: projectName
                ))
            }
        } catch {
            print("Error reading Claude projects: \(error)")
        }

        return projects
    }

    /// 모든 세션 가져오기 (활성 프로젝트만 파싱하여 최적화)
    public func getAllSessions(maxAgeDays: Int = 7) -> [AgentSession] {
        let runningDirs = getRunningClaudeWorkingDirs()

        // 실행 중인 프로세스가 없으면 빈 배열 반환
        if runningDirs.isEmpty {
            return []
        }

        // 실행 중인 프로젝트만 찾아서 파싱
        let activeProjects = getActiveProjects(runningDirs: runningDirs)

        var sessions: [AgentSession] = []

        for project in activeProjects {
            let projectSessions = parseProjectSessions(
                project: project,
                runningDirs: runningDirs,
                cutoffDate: Date.distantPast  // 활성 프로젝트는 날짜 제한 없음
            )
            sessions.append(contentsOf: projectSessions)
        }

        // 최근 활동 순으로 정렬
        return sessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// sessions-index.json 전체 구조
    private struct FullSessionsIndex: Decodable {
        let version: Int?
        let entries: [SessionEntry]?
        let originalPath: String?

        struct SessionEntry: Decodable {
            let sessionId: String?
            let fullPath: String?
            let projectPath: String?
            let modified: String?
        }
    }

    /// 경로를 폴더 이름 형식으로 변환 (예: /Users/intmain/workspace → -Users-intmain-workspace)
    private func dirNameFromPath(_ path: String) -> String {
        return path.replacingOccurrences(of: "/", with: "-")
    }

    /// 실행 중인 프로세스와 매칭되는 프로젝트만 찾기 (최적화: cwd를 폴더 이름으로 변환)
    private func getActiveProjects(runningDirs: [String: [Int]]) -> [ProjectMapping] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: basePath) else { return [] }
        if runningDirs.isEmpty { return [] }

        // 실행 중인 cwd를 폴더 이름 형식으로 변환한 Set
        var cwdDirNames = Set<String>()
        for cwd in runningDirs.keys {
            cwdDirNames.insert(dirNameFromPath(cwd))
        }

        var projects: [ProjectMapping] = []

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: basePath)

            for dirName in contents {
                let projectDir = "\(basePath)/\(dirName)"
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: projectDir, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                // cwd가 이 프로젝트 폴더 이름으로 시작하거나 일치하는지 확인
                var matched = false
                var matchedCwd: String?

                for cwd in runningDirs.keys {
                    let cwdDirName = dirNameFromPath(cwd)
                    // 정확히 일치하거나, cwd가 프로젝트의 하위 디렉토리인 경우
                    if cwdDirName == dirName || cwdDirName.hasPrefix(dirName + "-") {
                        matched = true
                        matchedCwd = cwd
                        break
                    }
                }

                if matched, let cwd = matchedCwd {
                    // sessions-index.json에서 실제 프로젝트 경로 읽기 (한 번만)
                    let indexFile = "\(projectDir)/sessions-index.json"
                    var projectPath = cwd
                    var projectName = (cwd as NSString).lastPathComponent

                    if let data = try? Data(contentsOf: URL(fileURLWithPath: indexFile)),
                       let index = try? JSONDecoder().decode(FullSessionsIndex.self, from: data) {
                        if let entries = index.entries, let firstEntry = entries.first,
                           let path = firstEntry.projectPath {
                            projectPath = path
                            projectName = (path as NSString).lastPathComponent
                        } else if let origPath = index.originalPath {
                            projectPath = origPath
                            projectName = (origPath as NSString).lastPathComponent
                        }
                    }

                    projects.append(ProjectMapping(
                        hash: dirName,
                        path: projectPath,
                        name: projectName
                    ))
                }
            }
        } catch {
            return []
        }

        return projects
    }

    /// 특정 프로젝트의 모든 세션 파싱
    private func parseProjectSessions(project: ProjectMapping, runningDirs: [String: [Int]], cutoffDate: Date) -> [AgentSession] {
        let projectDir = "\(basePath)/\(project.hash)"
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: projectDir) else { return [] }

        var sessions: [AgentSession] = []

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: projectDir)
            let logFiles = contents
                .filter { $0.hasSuffix(".jsonl") }
                .compactMap { fileName -> (name: String, path: String, mtime: Date)? in
                    let filePath = "\(projectDir)/\(fileName)"
                    guard let attrs = try? fileManager.attributesOfItem(atPath: filePath),
                          let mtime = attrs[.modificationDate] as? Date else { return nil }
                    return (fileName, filePath, mtime)
                }
                .sorted { $0.mtime > $1.mtime }

            // 이 프로젝트에서 실행 중인 프로세스 수
            let runningCount = countRunningProcesses(project.path, runningDirs: runningDirs)
            var activeSessionsAssigned = 0

            // 활성 세션만 필요하므로 runningCount 만큼만 파싱
            let filesToParse = logFiles.prefix(runningCount)

            for logFile in filesToParse {
                if let session = parseSingleLogFile(
                    logFile: logFile,
                    project: project,
                    isProcessActive: true  // 모두 활성
                ) {
                    sessions.append(session)
                }
            }
        } catch {
            print("Error parsing Claude project sessions: \(error)")
        }

        return sessions
    }

    /// 단일 로그 파일 파싱
    private func parseSingleLogFile(logFile: (name: String, path: String, mtime: Date), project: ProjectMapping, isProcessActive: Bool) -> AgentSession? {
        let entries = parseLogFileEntries(logFile.path)
        guard !entries.isEmpty else { return nil }

        // 세션 ID (파일명에서 추출)
        let sessionId = (logFile.name as NSString).deletingPathExtension

        // 토큰 집계
        var totalInput = 0
        var totalOutput = 0
        var cacheRead = 0
        var cacheWrite = 0
        var model = "claude-sonnet-4-20250514"
        var lastActivity = Date.distantPast
        var startTime = Date.distantFuture

        for entry in entries {
            if let usage = entry.message?.usage {
                totalInput += usage.input_tokens ?? 0
                totalOutput += usage.output_tokens ?? 0
                cacheRead += usage.cache_read_input_tokens ?? 0
                cacheWrite += usage.cache_creation_input_tokens ?? 0
            }

            if let entryModel = entry.message?.model {
                model = entryModel
            }

            if let timestampStr = entry.timestamp,
               let entryTime = parseTimestamp(timestampStr) {
                if entryTime < startTime { startTime = entryTime }
                if entryTime > lastActivity { lastActivity = entryTime }
            }
        }

        // 타임스탬프가 없으면 파일 시간 사용
        if startTime == Date.distantFuture {
            startTime = logFile.mtime
        }
        if lastActivity == Date.distantPast {
            lastActivity = logFile.mtime
        }

        // 비용 계산
        let tokens = TokenUsage(
            input: totalInput,
            output: totalOutput,
            cacheRead: cacheRead > 0 ? cacheRead : nil,
            cacheWrite: cacheWrite > 0 ? cacheWrite : nil
        )
        let cost = CostCalculator.calculate(agent: .claude, tokens: tokens)

        // 상태 결정
        let idleSeconds = Date().timeIntervalSince(lastActivity)
        let status: SessionStatus

        if isProcessActive {
            if idleSeconds < 5 {
                status = .running
            } else {
                status = .waiting
            }
        } else {
            status = .completed
        }

        return AgentSession(
            id: sessionId,
            agent: .claude,
            projectPath: project.path,
            projectName: project.name,
            status: status,
            tokens: tokens,
            cost: cost,
            startedAt: startTime,
            lastActivityAt: lastActivity,
            duration: lastActivity.timeIntervalSince(startTime),
            model: model,
            logFilePath: logFile.path
        )
    }

    /// JSONL 파일 파싱
    private func parseLogFileEntries(_ filePath: String) -> [LogEntry] {
        var entries: [LogEntry] = []

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return entries
        }

        let lines = content.components(separatedBy: .newlines)
        let decoder = JSONDecoder()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8) else { continue }

            if let entry = try? decoder.decode(LogEntry.self, from: data) {
                entries.append(entry)
            }
        }

        return entries
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

    /// 활성 세션만 가져오기
    public func getActiveSessions() -> [AgentSession] {
        getAllSessions(maxAgeDays: 365).filter { $0.status.isActive }
    }
}
