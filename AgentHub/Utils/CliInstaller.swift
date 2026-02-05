//
//  CliInstaller.swift
//  AgentHub
//
//  CLI 설치/제거 유틸리티
//

import Foundation
import AppKit

struct CliInstaller {
    static let installPath = "/usr/local/bin/agenthub"

    /// CLI가 설치되어 있는지 확인
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installPath)
    }

    /// 앱 번들 내 CLI 바이너리 경로
    static var cliBinaryPath: String? {
        Bundle.main.path(forAuxiliaryExecutable: "AgentHubCli")
    }

    /// CLI 설치 (심볼릭 링크 생성)
    static func install() {
        guard let binaryPath = cliBinaryPath else {
            showAlert(title: NSLocalizedString("설치 실패", comment: ""), message: NSLocalizedString("CLI 바이너리를 찾을 수 없습니다.", comment: ""))
            return
        }

        // /usr/local/bin 디렉토리 확인
        let binDir = "/usr/local/bin"
        if !FileManager.default.fileExists(atPath: binDir) {
            // 디렉토리 생성 필요 - 관리자 권한
            let script = "mkdir -p '\(binDir)'"
            runWithAdminPrivileges(script: script)
        }

        // 기존 파일 제거 후 심볼릭 링크 생성
        let script = """
        rm -f '\(installPath)' && ln -sf '\(binaryPath)' '\(installPath)'
        """

        if runWithAdminPrivileges(script: script) {
            showAlert(title: NSLocalizedString("설치 완료", comment: ""), message: NSLocalizedString("터미널에서 'agenthub' 명령어를 사용할 수 있습니다.", comment: ""))
        }
    }

    /// CLI 제거
    static func uninstall() {
        let script = "rm -f '\(installPath)'"

        if runWithAdminPrivileges(script: script) {
            showAlert(title: NSLocalizedString("제거 완료", comment: ""), message: NSLocalizedString("CLI가 제거되었습니다.", comment: ""))
        }
    }

    /// 관리자 권한으로 스크립트 실행
    @discardableResult
    private static func runWithAdminPrivileges(script: String) -> Bool {
        let appleScript = """
        do shell script "\(script)" with administrator privileges
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
                showAlert(title: NSLocalizedString("오류", comment: ""), message: error["NSAppleScriptErrorMessage"] as? String ?? NSLocalizedString("알 수 없는 오류", comment: ""))
                return false
            }
            return true
        }
        return false
    }

    /// 알림 표시
    private static func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = title.contains(NSLocalizedString("설치 실패", comment: "")) || title.contains(NSLocalizedString("오류", comment: "")) ? .warning : .informational
            alert.addButton(withTitle: NSLocalizedString("확인", comment: ""))
            alert.runModal()
        }
    }
}
