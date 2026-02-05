# AgentHub CLI

AI 코딩 에이전트(Claude, Codex, Gemini) 통합 모니터링 CLI 도구

## 설치

```bash
# 빌드
cd AgentHubCli
swift build -c release

# 설치 (선택사항)
cp .build/release/agenthub /usr/local/bin/
```

## 사용법

### 세션 목록 표시 (기본 명령)

```bash
# 활성 세션 목록
agenthub

# 모든 세션 (비활성 포함)
agenthub list --all

# 특정 에이전트만
agenthub list -t claude
agenthub list -t codex

# 색상 없이 출력
agenthub list --no-color
```

### 실시간 모니터링

```bash
# 기본 (2초 간격)
agenthub watch

# 5초 간격
agenthub watch -i 5

# 특정 에이전트만
agenthub watch -t claude
```

### 요약 정보

```bash
# 텍스트 요약
agenthub summary

# JSON 형식
agenthub summary --json
```

## 출력 예시

```
STATUS   AGENT    PROJECT                          TOKENS      COST       TIME
────────────────────────────────────────────────────────────────────────────────
●        Claude   my-project                       12.9K       $35.19     방금 전
◐        Claude   another-project                  2.9K        $6.61      10분 전
◐        Codex    third-project                    24.2K       $0.06      1시간 전
────────────────────────────────────────────────────────────────────────────────
Total: 3 sessions | 40.0K tokens | $41.86
```

### 상태 아이콘

- `●` 실행 중 (녹색)
- `◐` 대기 중 (노랑)
- `✓` 완료 (회색)
- `✗` 오류 (빨강)
- `○` 유휴 (회색)

## 공유 코드

이 CLI는 `AgentHubCore`를 공유하여 macOS 앱과 동일한 로직을 사용합니다:

- `AgentType` - 에이전트 종류 정의
- `SessionStatus` - 세션 상태
- `AgentSession` - 세션 데이터 모델
- `ClaudeLogParser` - Claude Code 로그 파싱
- `CodexLogParser` - Codex CLI 로그 파싱
- `GeminiLogParser` - Gemini CLI 로그 파싱
- `CostCalculator` - 토큰/비용 계산
