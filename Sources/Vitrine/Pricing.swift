import Foundation

// MARK: - Model pricing (USD per 1M tokens)

/// A hand-maintained snapshot of official per-model pricing. Prices drift with every model
/// generation and promo window — this is a well-cited snapshot (sources below), not a live feed.
/// Update it when `ModelInfo` gains new model families, or when a vendor reprices.
enum Pricing {
    struct ModelPrice {
        var inputPerM: Double
        var outputPerM: Double
        /// Discounted rate for a cache HIT (Anthropic prompt cache read; OpenAI's auto-detected
        /// `cached_input_tokens`). Falls back to `inputPerM` when a vendor doesn't discount it.
        var cacheReadPerM: Double? = nil
        /// Anthropic only: writing a NEW cache entry costs MORE than a fresh input token.
        /// No OpenAI/Gemini equivalent — caching there is auto-detected, never explicitly "written".
        var cacheWritePerM: Double? = nil
    }

    /// Sourced 2026-07-23 from official pricing pages:
    /// - Anthropic: platform.claude.com/docs/en/about-claude/pricing, claude.com/pricing
    /// - OpenAI: platform.openai.com/docs/pricing, developers.openai.com/api/docs/pricing
    /// - Google: ai.google.dev/gemini-api/docs/pricing
    /// Claude Sonnet 5 figures are its introductory price (through 2026-08-31); standard pricing
    /// afterward is input $3/output $15/cache-write $3.75/cache-read $0.30 per MTok.
    static let table: [String: ModelPrice] = [
        // Anthropic (Claude Code)
        "claude-opus-4-8": .init(inputPerM: 5, outputPerM: 25, cacheReadPerM: 0.5, cacheWritePerM: 6.25),
        "claude-sonnet-5": .init(inputPerM: 2, outputPerM: 10, cacheReadPerM: 0.2, cacheWritePerM: 2.5),
        "claude-haiku-4-5": .init(inputPerM: 1, outputPerM: 5, cacheReadPerM: 0.1, cacheWritePerM: 1.25),
        "claude-fable-5": .init(inputPerM: 10, outputPerM: 50, cacheReadPerM: 1, cacheWritePerM: 12.5),

        // OpenAI (Codex CLI) — current GPT-5.6 family + still-reachable legacy Codex models
        "gpt-5.6-sol": .init(inputPerM: 5, outputPerM: 30, cacheReadPerM: 0.5),
        "gpt-5.6-terra": .init(inputPerM: 2.5, outputPerM: 15, cacheReadPerM: 0.25),
        "gpt-5.6-luna": .init(inputPerM: 1, outputPerM: 6, cacheReadPerM: 0.1),
        "gpt-5.5": .init(inputPerM: 5, outputPerM: 30, cacheReadPerM: 0.5),
        "gpt-5.4-pro": .init(inputPerM: 30, outputPerM: 180),
        "gpt-5.4-mini": .init(inputPerM: 0.75, outputPerM: 4.5, cacheReadPerM: 0.075),
        "gpt-5.4-nano": .init(inputPerM: 0.2, outputPerM: 1.25, cacheReadPerM: 0.02),
        "gpt-5.4": .init(inputPerM: 2.5, outputPerM: 15, cacheReadPerM: 0.25),
        "gpt-5.3-codex": .init(inputPerM: 1.75, outputPerM: 14, cacheReadPerM: 0.175),
        "gpt-5.2-codex": .init(inputPerM: 1.75, outputPerM: 14, cacheReadPerM: 0.175),
        "gpt-5.2": .init(inputPerM: 1.75, outputPerM: 14, cacheReadPerM: 0.175),
        "gpt-5.1-codex-max": .init(inputPerM: 1.25, outputPerM: 10, cacheReadPerM: 0.125),
        "gpt-5.1-codex-mini": .init(inputPerM: 0.25, outputPerM: 2, cacheReadPerM: 0.025),
        "gpt-5.1-codex": .init(inputPerM: 1.25, outputPerM: 10, cacheReadPerM: 0.125),

        // Google (Gemini CLI) — sub-200k-token tier; long-context (>200k) runs ~2x on the models
        // that split by length, which Vitrine doesn't distinguish per-message, so this under-prices
        // very long Gemini sessions slightly. cacheReadPerM here is the API's cache-hit price, but
        // Vitrine's Gemini scanner doesn't currently report per-message cache hits (see below).
        "gemini-3.6-flash": .init(inputPerM: 1.5, outputPerM: 7.5, cacheReadPerM: 0.15),
        "gemini-3.5-flash": .init(inputPerM: 1.5, outputPerM: 9, cacheReadPerM: 0.15),
        "gemini-3.1-pro-preview": .init(inputPerM: 2, outputPerM: 12, cacheReadPerM: 0.2),
        "gemini-3.1-flash-lite": .init(inputPerM: 0.25, outputPerM: 1.5),
        "gemini-3-flash-preview": .init(inputPerM: 0.5, outputPerM: 3, cacheReadPerM: 0.05),
        "gemini-2.5-pro": .init(inputPerM: 1.25, outputPerM: 10, cacheReadPerM: 0.125),
        "gemini-2.5-flash": .init(inputPerM: 0.3, outputPerM: 2.5, cacheReadPerM: 0.03),
        "gemini-2.5-flash-lite": .init(inputPerM: 0.1, outputPerM: 0.4, cacheReadPerM: 0.01),
    ]

    /// Exact id match, then longest known-id prefix (covers dated suffixes like
    /// claude-haiku-4-5-20251001, or point releases not explicitly listed).
    static func price(for rawModelId: String) -> ModelPrice? {
        let id = rawModelId.lowercased()
        if let exact = table[id] { return exact }
        return table.filter { id.hasPrefix($0.key) }.max { $0.key.count < $1.key.count }?.value
    }
}

// MARK: - Cost estimation

extension SessionRecord {
    /// Whether this session's agent reports an exact input/cache-read/cache-write split, vs. only
    /// a lump input total with no cache visibility at all.
    var hasExactCacheAccounting: Bool { agent == .claude || agent == .codex }

    /// Input-side tokens with cache and fresh both counted exactly once, regardless of each
    /// agent's differing accounting shape — the denominator for a cache-hit ratio.
    /// Claude reports cache reads/writes as disjoint from `inputTokens`; Codex's `cacheReadTokens`
    /// is already a subset of `inputTokens`.
    var effectiveInputTokens: Int {
        agent == .claude ? inputTokens + (cacheReadTokens ?? 0) + (cacheCreationTokens ?? 0) : inputTokens
    }
    var cacheHitTokens: Int { cacheReadTokens ?? 0 }

    /// The token math split into priceable buckets — fresh (uncached) input, cache read, cache
    /// write, output — BEFORE multiplying by any price. Exposing this (rather than only a final
    /// USD number) is what lets the UI show the actual calculation, not just its result.
    /// `modelCount` divides a multi-model session's tokens evenly across the models it used,
    /// matching the convention `modelShare(by:)` already uses in Store.swift.
    struct CostComponents {
        var freshInput: Double
        var cacheRead: Double
        var cacheWrite: Double
        var output: Double
        /// True when the agent doesn't report its own cache split, so fresh/cacheRead here were
        /// approximated from `fallbackCacheHitRate` instead of this session's real numbers.
        var estimated: Bool
    }

    func costComponents(fallbackCacheHitRate: Double, modelCount: Double) -> CostComponents {
        let out = Double(outputTokens) / modelCount
        switch agent {
        case .claude:
            return CostComponents(freshInput: Double(inputTokens) / modelCount,
                                   cacheRead: Double(cacheReadTokens ?? 0) / modelCount,
                                   cacheWrite: Double(cacheCreationTokens ?? 0) / modelCount,
                                   output: out, estimated: false)
        case .codex:
            // inputTokens already includes the cached subset here — split it, don't add it again.
            let cacheRead = Double(cacheReadTokens ?? 0) / modelCount
            let fresh = max(0, Double(inputTokens) / modelCount - cacheRead)
            return CostComponents(freshInput: fresh, cacheRead: cacheRead, cacheWrite: 0,
                                   output: out, estimated: false)
        default:
            // No cache visibility at all (Gemini today) — approximate the split using the
            // cache-hit rate observed on sessions that DO report it exactly.
            let effectiveIn = Double(inputTokens) / modelCount
            let cacheRead = effectiveIn * fallbackCacheHitRate
            return CostComponents(freshInput: effectiveIn - cacheRead, cacheRead: cacheRead,
                                   cacheWrite: 0, output: out, estimated: true)
        }
    }

    /// Estimated USD cost of this session's model usage. `nil` when there's no pricing entry for
    /// any model it used, or no token accounting at all (Cursor / Windsurf / opencode today).
    func estimatedCost(fallbackCacheHitRate: Double) -> (usd: Double, estimated: Bool)? {
        guard totalTokens > 0, !models.isEmpty else { return nil }
        let prices = models.compactMap { Pricing.price(for: $0) }
        guard !prices.isEmpty else { return nil }
        let comp = costComponents(fallbackCacheHitRate: fallbackCacheHitRate, modelCount: Double(prices.count))
        var usd = 0.0
        for p in prices {
            usd += comp.freshInput * p.inputPerM + comp.cacheRead * (p.cacheReadPerM ?? p.inputPerM)
                 + comp.cacheWrite * (p.cacheWritePerM ?? p.inputPerM) + comp.output * p.outputPerM
        }
        return (usd / 1_000_000, comp.estimated)
    }
}

// MARK: - Visible per-model breakdown (the "show your work" view for the dashboard)

struct CostBreakdown: Identifiable {
    var id: String { modelLabel }
    var modelLabel: String
    var price: Pricing.ModelPrice
    var freshInput = 0.0
    var cacheRead = 0.0
    var cacheWrite = 0.0
    var output = 0.0
    var estimated = false

    var usd: Double {
        (freshInput * price.inputPerM + cacheRead * (price.cacheReadPerM ?? price.inputPerM)
       + cacheWrite * (price.cacheWritePerM ?? price.inputPerM) + output * price.outputPerM) / 1_000_000
    }

    /// The literal arithmetic, e.g. "12.3M 输入×$5.00/M + 890k 缓存写×$6.25/M + 输出 3.1M×$25.00/M".
    var formula: String {
        var parts: [String] = []
        if freshInput >= 1 { parts.append("\(Fmt.tokens(Int(freshInput))) 输入×\(Self.rate(price.inputPerM))") }
        if cacheWrite >= 1 { parts.append("\(Fmt.tokens(Int(cacheWrite))) 缓存写×\(Self.rate(price.cacheWritePerM ?? price.inputPerM))") }
        if cacheRead >= 1 { parts.append("\(Fmt.tokens(Int(cacheRead))) 缓存命中×\(Self.rate(price.cacheReadPerM ?? price.inputPerM))") }
        if output >= 1 { parts.append("\(Fmt.tokens(Int(output))) 输出×\(Self.rate(price.outputPerM))") }
        return parts.joined(separator: " + ")
    }

    private static func rate(_ v: Double) -> String { "$" + String(format: "%.2f", v) + "/M" }
}

extension Array where Element == SessionRecord {
    /// Share of "effective input" tokens that were a cache hit, averaged only over sessions with
    /// exact accounting (Claude, Codex). Used as the estimation basis for agents that report
    /// tokens but not a cache split (Gemini) — an honest approximation, not a guess from nothing.
    var averageCacheHitRate: Double {
        let known = filter(\.hasExactCacheAccounting)
        let totalIn = known.reduce(0) { $0 + $1.effectiveInputTokens }
        guard totalIn > 0 else { return 0 }
        let totalHit = known.reduce(0) { $0 + $1.cacheHitTokens }
        return Double(totalHit) / Double(totalIn)
    }

    /// Total estimated USD across every session with pricing data, plus whether any of it leaned
    /// on the cache-hit-rate approximation rather than an exact per-session breakdown.
    func totalEstimatedCost() -> (usd: Double, anyEstimated: Bool, priced: Int) {
        let rows = costBreakdown()
        let usd = rows.reduce(0) { $0 + $1.usd }
        let anyEstimated = rows.contains { $0.estimated }
        let priced = self.lazy.filter { s in
            s.totalTokens > 0 && s.models.contains { Pricing.price(for: $0) != nil }
        }.count
        return (usd, anyEstimated, priced)
    }

    /// Per-model cost breakdown, ranked most expensive first — the literal calculation behind the
    /// dashboard's total, one row per model actually used (not per session).
    func costBreakdown() -> [CostBreakdown] {
        let rate = averageCacheHitRate
        var buckets: [String: CostBreakdown] = [:]
        for s in self {
            guard s.totalTokens > 0, !s.models.isEmpty else { continue }
            let priced = s.models.compactMap { raw -> (String, Pricing.ModelPrice)? in
                guard let p = Pricing.price(for: raw) else { return nil }
                let label = ModelInfo.label(raw)
                return label.isEmpty ? nil : (label, p)
            }
            guard !priced.isEmpty else { continue }
            let n = Double(priced.count)
            let comp = s.costComponents(fallbackCacheHitRate: rate, modelCount: n)
            for (label, price) in priced {
                var bucket = buckets[label] ?? CostBreakdown(modelLabel: label, price: price)
                bucket.freshInput += comp.freshInput
                bucket.cacheRead += comp.cacheRead
                bucket.cacheWrite += comp.cacheWrite
                bucket.output += comp.output
                bucket.estimated = bucket.estimated || comp.estimated
                buckets[label] = bucket
            }
        }
        return buckets.values.sorted { $0.usd > $1.usd }
    }
}

enum CostFmt {
    /// Compact, locale-agnostic USD formatting matching `Fmt.tokens`' terseness.
    static func usd(_ v: Double) -> String {
        switch v {
        case 1_000...: return String(format: "$%.1fk", v / 1_000)
        case 1...: return String(format: "$%.2f", v)
        case 0.01...: return String(format: "$%.3f", v)
        case 0.0001...: return String(format: "<$0.01")
        default: return "$0"
        }
    }
}
