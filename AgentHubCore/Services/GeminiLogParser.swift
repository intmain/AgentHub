import Foundation
import CryptoKit

/// Gemini CLI 로그 파서
/// 참고: https://github.com/google-gemini/gemini-cli
///
/// Gemini CLI는 ~/.gemini/tmp/<projectHash>/chats/session-*.json에 세션 데이터 저장
public class GeminiLogParser {
    private let basePath: String
    private let runningDirsProvider: (() -> Set<String>)?

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.basePath = "\(home)/.gemini"
        self.runningDirsProvider = nil
    }

    init(basePath: String, runningDirsProvider: @escaping () -> Set<String>) {
        self.basePath = basePath
        self.runningDirsProvider = runningDirsProvider
    }

    /// Gemini 세션 파일 구조 (chats/session-*.json)
    private struct SessionFile: Decodable {
        let sessionId: String?
        let projectHash: String?
        let startTime: String?
        let lastUpdated: String?
        let messages: [Message]?

        struct Message: Decodable {
            let id: String?
            let timestamp: String?
            let type: String?
            let model: String?
            let tokens: Tokens?
        }

        struct Tokens: Decodable {
            let input: Int?
            let output: Int?
            let cached: Int?
            let total: Int?
        }
    }

    private struct ParsedSession {
        let sessionId: String
        let projectHash: String
        let startTime: Date
        let lastActivity: Date
        let model: String?
        let tokens: TokenUsage
        let logPath: String
    }

    /// 실행 중인 Gemini 프로세스의 작업 디렉토리 가져오기
    private func getRunningGeminiWorkingDirs() -> Set<String> {
        let pids = getRunningGeminiPIDs()
        guard !pids.isEmpty else { return [] }
        return getWorkingDirs(for: pids)
    }

    /// 다중 패턴으로 Gemini PID 탐지
    private func getRunningGeminiPIDs() -> Set<String> {
        let patterns: [[String]] = [
            ["-x", "gemini"],
            ["-x", "gemini-cli"],
            ["-f", "gemini-cli"],
            ["-f", "@google/gemini-cli"],
            ["-f", "bin/gemini"],
            ["-f", "google-gemini"]
        ]

        var pids = Set<String>()
        for pattern in patterns {
            pids.formUnion(runPgrep(arguments: pattern))
        }

        return pids
    }

    private func runPgrep(arguments: [String]) -> Set<String> {
        var pids = Set<String>()
        let pgrepTask = Process()
        pgrepTask.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrepTask.arguments = arguments

        let pipe = Pipe()
        pgrepTask.standardOutput = pipe
        pgrepTask.standardError = FileHandle.nullDevice

        do {
            try pgrepTask.run()
            pgrepTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            for line in output.components(separatedBy: .newlines) {
                let pid = line.trimmingCharacters(in: .whitespaces)
                if !pid.isEmpty {
                    pids.insert(pid)
                }
            }
        } catch {
            // 탐지 실패 시 빈 세트 반환
        }

        return pids
    }

    private func getWorkingDirs(for pids: Set<String>) -> Set<String> {
        var dirs = Set<String>()
        guard !pids.isEmpty else { return dirs }

        let lsofTask = Process()
        lsofTask.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsofTask.arguments = ["-a", "-d", "cwd", "-Fn", "-p", pids.joined(separator: ",")]

        let pipe = Pipe()
        lsofTask.standardOutput = pipe
        lsofTask.standardError = FileHandle.nullDevice

        do {
            try lsofTask.run()
            lsofTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            for line in output.components(separatedBy: .newlines) {
                if line.hasPrefix("n/") {
                    dirs.insert(String(line.dropFirst()))
                }
            }
        } catch {
            // cwd 확인 실패 시 빈 세트 반환
        }

        return dirs
    }

    private func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 모든 세션 가져오기 (활성 세션만)
    public func getAllSessions() -> [AgentSession] {
        let runningDirs = runningDirsProvider?() ?? getRunningGeminiWorkingDirs()
        if runningDirs.isEmpty { return [] }

        var hashToPath: [String: String] = [:]
        for dir in runningDirs {
            hashToPath[sha256Hex(dir)] = dir
        }

        let files = findAllSessionFiles()
        var sessions: [AgentSession] = []
        var seenProjects = Set<String>()  // 프로젝트당 최신 세션 1개

        for file in files {
            guard let parsed = parseSessionFile(file),
                  let projectPath = hashToPath[parsed.projectHash],
                  !seenProjects.contains(projectPath) else {
                continue
            }

            let projectName = (projectPath as NSString).lastPathComponent
            let idleSeconds = Date().timeIntervalSince(parsed.lastActivity)
            let status: SessionStatus = idleSeconds < 5 ? .running : .waiting

            let session = AgentSession(
                id: parsed.sessionId,
                agent: .gemini,
                projectPath: projectPath,
                projectName: projectName,
                status: status,
                tokens: parsed.tokens,
                cost: CostCalculator.calculate(agent: .gemini, tokens: parsed.tokens),
                startedAt: parsed.startTime,
                lastActivityAt: parsed.lastActivity,
                duration: max(0, parsed.lastActivity.timeIntervalSince(parsed.startTime)),
                model: parsed.model,
                logFilePath: parsed.logPath
            )

            sessions.append(session)
            seenProjects.insert(projectPath)
        }

        sessions.sort { $0.lastActivityAt > $1.lastActivityAt }
        return sessions
    }

    private func findAllSessionFiles() -> [(path: String, projectHash: String, mtime: Date)] {
        var files: [(path: String, projectHash: String, mtime: Date)] = []
        let fileManager = FileManager.default
        let tmpDir = "\(basePath)/tmp"

        guard fileManager.fileExists(atPath: tmpDir) else { return files }

        do {
            let projectHashes = try fileManager.contentsOfDirectory(atPath: tmpDir)
            for projectHash in projectHashes {
                let chatsDir = "\(tmpDir)/\(projectHash)/chats"
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: chatsDir, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                let sessionFiles = try fileManager.contentsOfDirectory(atPath: chatsDir)
                for file in sessionFiles where file.hasPrefix("session-") && file.hasSuffix(".json") {
                    let fullPath = "\(chatsDir)/\(file)"
                    if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                       let mtime = attrs[.modificationDate] as? Date {
                        files.append((fullPath, projectHash, mtime))
                    }
                }
            }
        } catch {
            print("Error reading Gemini sessions: \(error)")
        }

        files.sort { $0.mtime > $1.mtime }
        return files
    }

    private func parseSessionFile(_ file: (path: String, projectHash: String, mtime: Date)) -> ParsedSession? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file.path)),
              let sessionFile = try? JSONDecoder().decode(SessionFile.self, from: data) else {
            return nil
        }

        let sessionId = sessionFile.sessionId
            ?? ((file.path as NSString).lastPathComponent as NSString).deletingPathExtension
        let projectHash = sessionFile.projectHash ?? file.projectHash

        var inputTokens = 0
        var outputTokens = 0
        var cachedTokens = 0
        var model: String?
        var firstMessageTime: Date?
        var lastMessageTime: Date?

        for message in sessionFile.messages ?? [] {
            if let tokens = message.tokens {
                inputTokens += tokens.input ?? 0
                outputTokens += tokens.output ?? 0
                cachedTokens += tokens.cached ?? 0
            }

            if let messageModel = message.model, !messageModel.isEmpty {
                model = messageModel
            }

            if let timestamp = message.timestamp, let date = parseTimestamp(timestamp) {
                if firstMessageTime == nil || date < firstMessageTime! {
                    firstMessageTime = date
                }
                if lastMessageTime == nil || date > lastMessageTime! {
                    lastMessageTime = date
                }
            }
        }

        let parsedStartTime = sessionFile.startTime.flatMap(parseTimestamp)
        let parsedLastUpdated = sessionFile.lastUpdated.flatMap(parseTimestamp)
        let startTime = parsedStartTime ?? firstMessageTime ?? file.mtime
        let lastActivity = parsedLastUpdated ?? lastMessageTime ?? file.mtime

        let tokens = TokenUsage(
            input: inputTokens,
            output: outputTokens,
            cacheRead: cachedTokens > 0 ? cachedTokens : nil
        )

        return ParsedSession(
            sessionId: sessionId,
            projectHash: projectHash,
            startTime: startTime,
            lastActivity: max(startTime, lastActivity),
            model: model,
            tokens: tokens,
            logPath: file.path
        )
    }

    /// 타임스탬프 파싱
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
        getAllSessions().filter { $0.status.isActive }
    }
}
