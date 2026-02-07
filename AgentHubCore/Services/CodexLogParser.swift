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

    /// 세션 파일 파싱 (선택적 디코딩 최적화)
    ///
    /// 최적화 전략:
    /// - Data 레벨에서 줄 단위 처리 (String 중간 배열 생성 없음)
    /// - "session_meta" 포함 라인만 SessionMeta 디코딩
    /// - "token_count" 포함 라인만 EventMessage 디코딩
    /// - 마지막 라인에서 timestamp 문자열 추출 (풀 디코딩 없이)
    private func parseSessionFile(_ filePath: String, mtime: Date, runningDirs: Set<String>) -> AgentSession? {
        guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              !fileData.isEmpty else {
            return nil
        }

        let decoder = JSONDecoder()
        let sessionMetaMarker = Data("\"session_meta\"".utf8)
        let tokenCountMarker = Data("\"token_count\"".utf8)
        let timestampMarker = Data("\"timestamp\":\"".utf8)

        var sessionId: String?
        var cwd: String?
        var cliVersion: String?
        var startTime: Date?
        var lastTime: Date?
        var totalInputTokens = 0
        var totalOutputTokens = 0
        var lastLineStart = fileData.startIndex

        var lineStart = fileData.startIndex
        while lineStart < fileData.endIndex {
            // 줄 끝 찾기
            var lineEnd = lineStart
            while lineEnd < fileData.endIndex && fileData[lineEnd] != UInt8(ascii: "\n") {
                lineEnd = fileData.index(after: lineEnd)
            }

            let lineRange = lineStart..<lineEnd
            if lineRange.count > 0 {
                let lineData = fileData[lineRange]
                let isEmpty = lineData.allSatisfy { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") || $0 == UInt8(ascii: "\r") }

                if !isEmpty {
                    lastLineStart = lineStart

                    // "session_meta" 포함 라인만 SessionMeta 디코딩
                    if sessionId == nil && lineData.range(of: sessionMetaMarker) != nil {
                        if let meta = try? decoder.decode(SessionMeta.self, from: lineData),
                           meta.type == "session_meta" {
                            sessionId = meta.payload?.id
                            cwd = meta.payload?.cwd
                            cliVersion = meta.payload?.cli_version
                            if let ts = meta.timestamp {
                                startTime = parseTimestamp(ts)
                            }
                        }
                    }
                    // "token_count" 포함 라인만 EventMessage 디코딩
                    else if lineData.range(of: tokenCountMarker) != nil {
                        if let event = try? decoder.decode(EventMessage.self, from: lineData),
                           event.type == "event_msg",
                           event.payload?.type == "token_count",
                           let usage = event.payload?.info?.total_token_usage {
                            totalInputTokens = usage.input_tokens ?? totalInputTokens
                            totalOutputTokens = usage.output_tokens ?? totalOutputTokens
                        }
                    }
                }
            }

            lineStart = lineEnd < fileData.endIndex ? fileData.index(after: lineEnd) : fileData.endIndex
        }

        // 마지막 비어있지 않은 라인에서 timestamp 추출
        let lastLineEnd = fileData[lastLineStart...].firstIndex(of: UInt8(ascii: "\n")) ?? fileData.endIndex
        let lastLineData = fileData[lastLineStart..<lastLineEnd]
        if let ts = extractTimestampFromData(lastLineData, marker: timestampMarker) {
            lastTime = ts
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
            status = idleSeconds < 5 ? .running : .waiting
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

    // MARK: - DateFormatter 캐싱 (static으로 1회만 생성)

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 타임스탬프 파싱 (ISO8601) - static formatter 사용
    private func parseTimestamp(_ string: String) -> Date? {
        if let date = Self.iso8601WithFractional.date(from: string) {
            return date
        }
        return Self.iso8601Basic.date(from: string)
    }

    /// Data 슬라이스에서 timestamp 추출 (String 변환 최소화)
    private func extractTimestampFromData(_ lineData: Data.SubSequence, marker: Data) -> Date? {
        guard let markerRange = lineData.range(of: marker) else { return nil }
        let start = markerRange.upperBound
        guard let quoteIndex = lineData[start...].firstIndex(of: UInt8(ascii: "\"")) else { return nil }
        guard let tsString = String(data: lineData[start..<quoteIndex], encoding: .utf8) else { return nil }
        return parseTimestamp(tsString)
    }

    /// 모든 세션 가져오기 (활성 프로세스만)
    public func getAllSessions(maxAgeDays: Int = 7) -> [AgentSession] {
        let t0 = CFAbsoluteTimeGetCurrent()
        let runningDirs = getRunningCodexWorkingDirs()
        let t1 = CFAbsoluteTimeGetCurrent()

        // 실행 중인 프로세스가 없으면 빈 배열 반환
        if runningDirs.isEmpty {
            NSLog("[Perf:Codex] pgrep+lsof: %.0fms (no running)", (t1 - t0) * 1000)
            return []
        }

        let sessionFiles = findAllSessionFiles()
        let t2 = CFAbsoluteTimeGetCurrent()

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
        let t3 = CFAbsoluteTimeGetCurrent()

        NSLog("[Perf:Codex] pgrep+lsof: %.0fms | findFiles: %.0fms | parseSessions: %.0fms | total: %.0fms (%d files, %d sessions)",
              (t1 - t0) * 1000, (t2 - t1) * 1000, (t3 - t2) * 1000, (t3 - t0) * 1000,
              sessionFiles.count, sessions.count)

        return sessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// 활성 세션만 가져오기
    public func getActiveSessions() -> [AgentSession] {
        getAllSessions(maxAgeDays: 365).filter { $0.status.isActive }
    }
}
