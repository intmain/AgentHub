# AgentHub macOS App

AI 코딩 에이전트(Claude Code, Codex CLI, Gemini CLI) 통합 모니터링 macOS 네이티브 앱

## 주요 기능

### 1. 멀티 에이전트 세션 모니터링
- **Claude Code**, **Codex CLI**, **Gemini CLI** 세션 실시간 추적
- 토큰 사용량 (Input/Output/Cache) 집계
- 예상 비용 계산 (에이전트별 가격 모델 적용)
- 세션 상태 표시 (실행 중/대기 중/완료)

### 2. 메뉴바 앱
- 우상단 메뉴바에서 활성 세션 수 표시
- 클릭 시 세션 목록 팝오버
- 오른쪽 클릭으로 컨텍스트 메뉴 (대시보드 열기/앱 종료)

### 3. 대시보드
- 세션 목록 및 상세 정보
- 실시간 로그 뷰어 (JSONL 파싱, 메시지 타입별 색상 구분)
- 프로젝트 폴더 열기 (Finder/VSCode/Terminal)

### 4. CLI 도구
- 앱 내에서 CLI 설치/제거 (`/usr/local/bin/agenthub`)
- 터미널에서 세션 모니터링 가능
- `agenthub`, `agenthub watch`, `agenthub summary` 명령어

### 5. 위젯 (WidgetKit)
- Small/Medium/Large 3가지 크기
- 활성 세션 수, 총 비용 표시

---

## 프로젝트 구조

```
AgentHubMac/
├── AgentHub/                    # 메인 앱 타겟
│   ├── App/
│   │   ├── AgentHubApp.swift    # @main, MenuBarExtra + Window
│   │   └── AppDelegate.swift    # 생명주기, 오른쪽 클릭 메뉴
│   ├── Views/
│   │   ├── MenuBarView.swift    # 메뉴바 팝오버
│   │   └── DashboardView.swift  # 대시보드 (800줄+)
│   ├── ViewModels/
│   │   └── SessionViewModel.swift
│   ├── Utils/
│   │   └── CliInstaller.swift   # CLI 설치/제거
│   └── Resources/
│       ├── en.lproj/Localizable.strings
│       └── ko.lproj/Localizable.strings
│
├── AgentHubCore/                # 공유 프레임워크 (앱 + CLI)
│   ├── Models/
│   │   ├── AgentType.swift      # claude, codex, gemini
│   │   ├── SessionStatus.swift  # running, waiting, completed
│   │   ├── AgentSession.swift   # 세션 데이터 모델
│   │   └── CostCalculator.swift # 토큰/비용 계산
│   └── Services/
│       ├── ClaudeLogParser.swift
│       ├── CodexLogParser.swift
│       └── GeminiLogParser.swift
│
├── AgentHubCli/                 # CLI 타겟
│   └── main.swift               # list, watch, summary 명령어
│
└── AgentHubWidget/              # WidgetKit 타겟
    ├── AgentHubWidget.swift
    └── Views/
        ├── SmallWidgetView.swift
        ├── MediumWidgetView.swift
        └── LargeWidgetView.swift
```

---

## 핵심 구현 세부사항

### 1. 로그 파싱

각 에이전트의 로그 파일 위치와 형식:

| 에이전트 | 경로 | 형식 |
|---------|------|------|
| Claude Code | `~/.claude/projects/{hash}/*.jsonl` | JSONL |
| Codex CLI | `~/.codex/sessions/YYYY/MM/DD/*.jsonl` | JSONL |
| Gemini CLI | `~/.gemini/tmp/<projectHash>/chats/session-*.json` | JSON |

**Claude 로그 파싱 최적화** (8초 → 1초):
```swift
// 1. pgrep으로 실행 중인 claude 프로세스 PID 목록
pgrep -x claude

// 2. lsof로 모든 PID의 작업 디렉토리 한번에 가져오기
lsof -a -d cwd -Fn -p <pid1,pid2,...>

// 3. 폴더 이름 매칭으로 활성 프로젝트만 파싱
// /Users/foo/workspace → -Users-foo-workspace

// 4. 실행 중인 프로세스 수만큼만 로그 파일 파싱

// 5. 세 파서 병렬 실행 (DispatchGroup)
```

### 2. 프로세스 상태 감지

```swift
private func getRunningClaudeWorkingDirs() -> [String: [Int]] {
    // pgrep -x claude → PID 목록
    // lsof -a -d cwd -Fn -p <pids> → 작업 디렉토리
    // cwd를 폴더 이름 형식으로 변환하여 프로젝트 매칭
}
```

### 3. 실시간 로그 뷰어

```swift
class LogViewerViewModel: ObservableObject {
    private var source: DispatchSourceFileSystemObject?

    func startWatching(path: String?) {
        // FileHandle로 파일 열기
        // DispatchSource.makeFileSystemObjectSource로 변경 감지
        // .write, .extend 이벤트 모니터링
        // 새 내용 파싱하여 UI 업데이트
    }
}
```

JSONL 파싱하여 메시지 타입별 표시:
- 🟣 Assistant (sparkles 아이콘)
- 🔵 User (person 아이콘)
- ⚫ System (gear 아이콘)
- 🟠 Tool (wrench 아이콘)

### 4. 동적 Dock 표시

```swift
// 앱 시작 시 - 메뉴바만
NSApp.setActivationPolicy(.accessory)

// 대시보드 열 때 - Dock에 표시
openWindow(id: "dashboard")
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    NSApp.unhide(nil)
    window.makeKeyAndOrderFront(nil)
    NSApp.setActivationPolicy(.regular)
}

// 대시보드 닫을 때 - Dock에서 숨김
NSApp.setActivationPolicy(.accessory)
```

**주의**: `setActivationPolicy`는 비동기적이므로 100ms 지연 필요

### 5. CLI 설치

```swift
struct CliInstaller {
    static let installPath = "/usr/local/bin/agenthub"

    static func install() {
        // Bundle.main.path(forAuxiliaryExecutable: "AgentHubCli")
        // AppleScript로 관리자 권한 요청
        // ln -sf로 심볼릭 링크 생성
    }
}
```

### 6. 다국어 지원

한국어 키를 사용하여 코드 변경 최소화:
```
// en.lproj/Localizable.strings
"설정" = "Settings";
"활성 세션" = "Active Sessions";

// ko.lproj/Localizable.strings
"설정" = "설정";
"활성 세션" = "활성 세션";
```

SwiftUI `Text("설정")`은 자동으로 Localizable.strings 참조

### 7. 비용 계산

```swift
struct CostCalculator {
    static func calculate(agent: AgentType, tokens: TokenUsage) -> Double {
        switch agent {
        case .claude:
            // Input: $3/1M, Output: $15/1M
            // Cache Read: $0.30/1M, Cache Write: $3.75/1M
        case .codex:
            // Input: $2.5/1M, Output: $10/1M
        case .gemini:
            // Input: $0.10/1M, Output: $0.40/1M
        }
    }
}
```

---

## 기술 스택

- **Swift 5** / **SwiftUI**
- **AppKit** (NSStatusItem, NSApplication)
- **WidgetKit** (macOS 위젯)
- **DispatchSource** (파일 감시)
- **Combine** (데이터 바인딩)

---

## 빌드 및 실행

```bash
# Xcode에서 빌드
xcodebuild -project AgentHub.xcodeproj -scheme AgentHub build

# CLI만 빌드
xcodebuild -project AgentHub.xcodeproj -scheme AgentHubCli build
```

---

## 향후 개선 가능 사항

1. **MCP 서버 연동** - 웹 Claude와 컨텍스트 공유
2. **세션 히스토리** - 과거 세션 조회 및 통계
3. **알림** - 세션 시작/종료/비용 임계값 알림
4. **단축키** - 전역 단축키로 대시보드 토글
