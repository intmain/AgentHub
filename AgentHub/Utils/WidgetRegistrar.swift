import Foundation
import WidgetKit

struct WidgetRegistrar {
    static let widgetBundleId = "com.agenthub.app.widget"

    enum Status: Equatable {
        case registered
        case notRegistered
        case unknown
    }

    /// 위젯 등록 상태 확인
    static func checkStatus() -> Status {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-m", "-DAD", "-p", "com.apple.widgetkit-extension"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return .unknown
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        for line in output.components(separatedBy: "\n") {
            if line.contains(widgetBundleId) {
                return .registered
            }
        }

        return .notRegistered
    }

    /// 위젯 익스텐션 등록
    static func register() -> Bool {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL else { return false }
        let appexPath = plugInsURL.appendingPathComponent("AgentHubWidgetExtension.appex").path

        guard FileManager.default.fileExists(atPath: appexPath) else { return false }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-a", appexPath]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }

        // 위젯 타임라인 갱신 트리거
        WidgetCenter.shared.reloadAllTimelines()

        return task.terminationStatus == 0
    }
}
