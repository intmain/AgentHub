import Foundation

/// Gemini CLI 로그 파서
/// 참고: https://github.com/google-gemini/gemini-cli
///
/// Gemini CLI는 ~/.gemini/logs/에 세션 데이터 저장
public class GeminiLogParser {
    private let basePath: String

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.basePath = "\(home)/.gemini"
    }

    /// Gemini 로그 엔트리 구조
    private struct LogEntry: Decodable {
        let timestamp: String?
        let type: String?
        let model: String?
        let usage: Usage?
        let content: String?

        struct Usage: Decodable {
            let promptTokenCount: Int?
            let candidatesTokenCount: Int?
            let totalTokenCount: Int?
            let cachedContentTokenCount: Int?
        }
    }

    /// 모든 세션 가져오기
    public func getAllSessions() -> [AgentSession] {
        var sessions: [AgentSession] = []
        let fileManager = FileManager.default
        let logsDir = "\(basePath)/logs"

        guard fileManager.fileExists(atPath: logsDir) else { return sessions }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: logsDir)
            let logFiles = contents
                .filter { $0.hasSuffix(".jsonl") || $0.hasSuffix(".log") }
                .compactMap { fileName -> (name: String, path: String, mtime: Date)? in
                    let filePath = "\(logsDir)/\(fileName)"
                    guard let attrs = try? fileManager.attributesOfItem(atPath: filePath),
                          let mtime = attrs[.modificationDate] as? Date else { return nil }
                    return (fileName, filePath, mtime)
                }
                .sorted { $0.mtime > $1.mtime }

            for file in logFiles {
                if let session = parseLogFile(file) {
                    sessions.append(session)
                }
            }
        } catch {
            print("Error reading Gemini logs: \(error)")
        }

        return sessions
    }

    /// 로그 파일 파싱
    private func parseLogFile(_ file: (name: String, path: String, mtime: Date)) -> AgentSession? {
        guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        let decoder = JSONDecoder()

        var totalInput = 0
        var totalOutput = 0
        var cached = 0
        var model = "gemini-2.0-flash"
        var startTime = Date.distantFuture
        var lastActivity = file.mtime

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8) else { continue }

            guard let entry = try? decoder.decode(LogEntry.self, from: data) else { continue }

            if let usage = entry.usage {
                totalInput += usage.promptTokenCount ?? 0
                totalOutput += usage.candidatesTokenCount ?? 0
                cached += usage.cachedContentTokenCount ?? 0
            }

            if let entryModel = entry.model {
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
            startTime = file.mtime
        }

        // 상태 추정
        let idleMinutes = Date().timeIntervalSince(lastActivity) / 60
        let status: SessionStatus
        if idleMinutes < 1 {
            status = .running
        } else if idleMinutes < 5 {
            status = .waiting
        } else {
            status = .idle
        }

        // 토큰/비용 계산
        let tokens = TokenUsage(
            input: totalInput,
            output: totalOutput,
            cacheRead: cached > 0 ? cached : nil
        )
        let cost = CostCalculator.calculate(agent: .gemini, tokens: tokens)

        // 세션 ID
        let sessionId = (file.name as NSString).deletingPathExtension

        return AgentSession(
            id: sessionId,
            agent: .gemini,
            projectPath: basePath,
            projectName: String(sessionId.prefix(12)),
            status: status,
            tokens: tokens,
            cost: cost,
            startedAt: startTime,
            lastActivityAt: lastActivity,
            duration: lastActivity.timeIntervalSince(startTime),
            model: model,
            logFilePath: file.path
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
