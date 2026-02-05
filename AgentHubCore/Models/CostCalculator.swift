import Foundation

/// 에이전트별 토큰 비용 계산기
public struct CostCalculator {
    /// 에이전트별 가격 정보 ($/1M tokens)
    public struct Pricing {
        let inputPer1M: Double
        let outputPer1M: Double
        let cacheReadPer1M: Double
        let cacheWritePer1M: Double

        public init(
            inputPer1M: Double,
            outputPer1M: Double,
            cacheReadPer1M: Double = 0,
            cacheWritePer1M: Double = 0
        ) {
            self.inputPer1M = inputPer1M
            self.outputPer1M = outputPer1M
            self.cacheReadPer1M = cacheReadPer1M
            self.cacheWritePer1M = cacheWritePer1M
        }
    }

    /// 에이전트별 기본 가격
    public static let pricing: [AgentType: Pricing] = [
        // Claude Sonnet 4: $3/1M input, $15/1M output, $0.30/1M cache read
        .claude: Pricing(inputPer1M: 3.0, outputPer1M: 15.0, cacheReadPer1M: 0.30),

        // GPT-4o: $2.50/1M input, $10/1M output
        .codex: Pricing(inputPer1M: 2.5, outputPer1M: 10.0),

        // Gemini 2.0 Flash: $0.10/1M input, $0.40/1M output
        .gemini: Pricing(inputPer1M: 0.1, outputPer1M: 0.4),

        // OpenCode (varies by model, using GPT-4 estimates)
        .opencode: Pricing(inputPer1M: 2.5, outputPer1M: 10.0),

        // Cursor (varies by model)
        .cursor: Pricing(inputPer1M: 3.0, outputPer1M: 15.0)
    ]

    /// 비용 계산
    public static func calculate(
        agent: AgentType,
        tokens: TokenUsage
    ) -> Double {
        guard let price = pricing[agent] else { return 0 }

        let inputCost = Double(tokens.input) * price.inputPer1M / 1_000_000
        let outputCost = Double(tokens.output) * price.outputPer1M / 1_000_000
        let cacheReadCost = Double(tokens.cacheRead ?? 0) * price.cacheReadPer1M / 1_000_000
        let cacheWriteCost = Double(tokens.cacheWrite ?? 0) * price.cacheWritePer1M / 1_000_000

        return inputCost + outputCost + cacheReadCost + cacheWriteCost
    }

    /// 전체 세션 비용 합계
    public static func totalCost(sessions: [AgentSession]) -> Double {
        sessions.reduce(0) { $0 + $1.cost }
    }

    /// 전체 토큰 합계
    public static func totalTokens(sessions: [AgentSession]) -> TokenUsage {
        var total = TokenUsage()
        for session in sessions {
            total.input += session.tokens.input
            total.output += session.tokens.output
            total.total += session.tokens.total
            if let cacheRead = session.tokens.cacheRead {
                total.cacheRead = (total.cacheRead ?? 0) + cacheRead
            }
            if let cacheWrite = session.tokens.cacheWrite {
                total.cacheWrite = (total.cacheWrite ?? 0) + cacheWrite
            }
        }
        return total
    }
}

extension CostCalculator {
    /// 포맷된 비용 문자열
    public static func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        } else if cost < 1 {
            return String(format: "$%.2f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }

    /// 포맷된 토큰 수
    public static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}
