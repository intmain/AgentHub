import Foundation

/// Gemini CLI 로그 파서
/// 참고: https://github.com/google-gemini/gemini-cli
///
/// Gemini CLI는 ~/.gemini/tmp/<projectHash>/chats/session-*.json에 세션 데이터 저장
public class GeminiLogParser {
    private let basePath: String
    private let runningProjectMappingsProvider: (() -> [String: String])?

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.basePath = "\(home)/.gemini"
        self.runningProjectMappingsProvider = nil
    }

    init(basePath: String, runningProjectMappingsProvider: @escaping () -> [String: String]) {
        self.basePath = basePath
        self.runningProjectMappingsProvider = runningProjectMappingsProvider
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

    /// 실행 중인 Gemini 프로세스의 projectHash -> 작업 디렉토리 매핑 가져오기
    private func getRunningGeminiProjectMappings() -> [String: String] {
        let pids = getRunningGeminiPIDs()
        guard !pids.isEmpty else { return [:] }

        let cwdByPID = getWorkingDirsByPID(for: pids)
        return resolveProjectMappings(cwdByPID: cwdByPID)
    }

    /// Gemini PID 탐지 (단일 pgrep 호출로 통합)
    private func getRunningGeminiPIDs() -> Set<String> {
        // 모든 Gemini 관련 프로세스(gemini, gemini-cli, @google/gemini-cli, bin/gemini, google-gemini)는
        // 커맨드라인에 "gemini"를 포함하므로 단일 호출로 충분.
        // false positive PID는 이후 projectHash 매칭에서 걸러짐.
        return runPgrep(arguments: ["-f", "gemini"])
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

    /// PID별 작업 디렉토리(cwd) 조회
    private func getWorkingDirsByPID(for pids: Set<String>) -> [String: String] {
        var cwdByPID: [String: String] = [:]
        guard !pids.isEmpty else { return cwdByPID }

        let pidList = pids.sorted().joined(separator: ",")
        guard let output = runLsof(arguments: ["-a", "-d", "cwd", "-FpFn", "-p", pidList]) else {
            return cwdByPID
        }

        var currentPID: String?
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("p") {
                let pid = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                currentPID = pid.isEmpty ? nil : pid
            } else if line.hasPrefix("n"), let pid = currentPID {
                let path = String(line.dropFirst())
                if path.hasPrefix("/") {
                    cwdByPID[pid] = path
                }
            }
        }

        return cwdByPID
    }

    private func runLsof(arguments: [String]) -> String? {
        let lsofTask = Process()
        lsofTask.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsofTask.arguments = arguments

        let pipe = Pipe()
        lsofTask.standardOutput = pipe
        lsofTask.standardError = FileHandle.nullDevice

        do {
            try lsofTask.run()
            lsofTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return nil
        }
    }

    /// Gemini CLI의 projectHash는 프로젝트 절대 경로의 SHA-256(hex, lowercase)이다.
    private func normalizeProjectPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("/") else {
            return nil
        }

        let normalized = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL.path
        if normalized == "/" {
            return normalized
        }

        return normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
    }

    /// 실행 중인 cwd를 Gemini projectHash로 변환해 hash -> path 매핑 생성.
    /// 동일 hash에 서로 다른 경로가 매핑되면 모호한 매핑으로 간주해 제외한다.
    private func resolveProjectMappings(cwdByPID: [String: String]) -> [String: String] {
        var hashToPaths: [String: Set<String>] = [:]

        for cwd in cwdByPID.values {
            guard let normalizedPath = normalizeProjectPath(cwd) else { continue }
            let hash = sha256Hex(normalizedPath)
            hashToPaths[hash, default: []].insert(normalizedPath)
        }

        var resolved: [String: String] = [:]
        for (hash, paths) in hashToPaths where paths.count == 1 {
            if let path = paths.first {
                resolved[hash] = path
            }
        }

        return resolved
    }

    private static let sha256RoundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    private static let sha256InitialHash: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    private func sha256Hex(_ input: String) -> String {
        var message = Array(input.utf8)
        let bitLength = UInt64(message.count) * 8

        message.append(0x80)
        while (message.count % 64) != 56 {
            message.append(0)
        }

        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var hash = Self.sha256InitialHash

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var words = Array(repeating: UInt32(0), count: 64)

            for i in 0..<16 {
                let index = chunkStart + (i * 4)
                words[i] =
                    (UInt32(message[index]) << 24) |
                    (UInt32(message[index + 1]) << 16) |
                    (UInt32(message[index + 2]) << 8) |
                    UInt32(message[index + 3])
            }

            for i in 16..<64 {
                let s0 = Self.rotateRight(words[i - 15], by: 7) ^
                    Self.rotateRight(words[i - 15], by: 18) ^
                    (words[i - 15] >> 3)
                let s1 = Self.rotateRight(words[i - 2], by: 17) ^
                    Self.rotateRight(words[i - 2], by: 19) ^
                    (words[i - 2] >> 10)
                words[i] = words[i - 16] &+ s0 &+ words[i - 7] &+ s1
            }

            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]

            for i in 0..<64 {
                let s1 = Self.rotateRight(e, by: 6) ^ Self.rotateRight(e, by: 11) ^ Self.rotateRight(e, by: 25)
                let ch = (e & f) ^ ((~e) & g)
                let temp1 = h &+ s1 &+ ch &+ Self.sha256RoundConstants[i] &+ words[i]
                let s0 = Self.rotateRight(a, by: 2) ^ Self.rotateRight(a, by: 13) ^ Self.rotateRight(a, by: 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj

                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
            hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g
            hash[7] = hash[7] &+ h
        }

        return hash.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }

    /// 모든 세션 가져오기 (활성 세션만)
    public func getAllSessions() -> [AgentSession] {
        let hashToPath = runningProjectMappingsProvider?() ?? getRunningGeminiProjectMappings()
        if hashToPath.isEmpty { return [] }

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
        let projectHash = (sessionFile.projectHash ?? file.projectHash).lowercased()

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
