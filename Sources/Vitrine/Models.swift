import SwiftUI
import AppKit

// MARK: - Agents

enum AgentKind: String, Codable, CaseIterable, Identifiable {
    case claude, codex, gemini, opencode, cursor, windsurf, other
    var id: String { rawValue }

    var display: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .opencode: "opencode"
        case .cursor: "Cursor"
        case .windsurf: "Windsurf"
        case .other: "Other"
        }
    }

    var color: Color {
        switch self {
        case .claude: V.coral
        case .codex: V.teal
        case .gemini: V.sky
        case .opencode: V.violet
        case .cursor: V.indigo
        case .windsurf: V.mint
        case .other: .gray
        }
    }

    var symbol: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .gemini: "sparkle"
        case .opencode: "terminal"
        case .cursor: "cursorarrow.rays"
        case .windsurf: "wind"
        case .other: "cube"
        }
    }
}

// MARK: - Composition weighting

/// How composition donuts weight each session: by message count, or by token throughput.
enum ShareMetric: String, CaseIterable, Identifiable {
    case messages, tokens
    var id: String { rawValue }
    var display: String { self == .messages ? "消息" : "Tokens" }
    var subtitle: String { self == .messages ? "按消息量占比" : "按 token 吞吐占比" }
    func weight(_ s: SessionRecord) -> Int {
        self == .messages ? Swift.max(1, s.messageCount) : s.totalTokens
    }
}

// MARK: - Model families (for the model-distribution donut)

enum ModelInfo {
    /// Prettify a raw model id while KEEPING its specific version — the distribution should show
    /// the actual models a run used, not a coarse family. "Codex" is a CLI, never a model, so its
    /// underlying ids (gpt-5.3-codex, gpt-5.2, …) surface individually.
    ///   claude-opus-4-8            → "Claude Opus 4.8"
    ///   claude-haiku-4-5-20251001  → "Claude Haiku 4.5"   (trailing date dropped)
    ///   gpt-5.3-codex              → "GPT-5.3 Codex"
    ///   gpt-5.1-codex-max          → "GPT-5.1 Codex Max"
    ///   gemini-2.5-pro             → "Gemini 2.5 Pro"
    /// Returns "" for placeholder ids (synthetic/empty) so callers drop them.
    static func label(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.isEmpty || s.contains("synthetic") || s == "<none>" { return "" }

        if s.hasPrefix("claude") {
            let p = raw.split(separator: "-").map(String.init)
            guard p.count >= 2 else { return raw }
            let family = p[1].capitalized
            // Version = the short numeric segments joined by "." (skip 8-digit date stamps).
            let ver = p.dropFirst(2).filter { $0.count < 5 && $0.allSatisfy(\.isNumber) }
            return "Claude \(family)" + (ver.isEmpty ? "" : " " + ver.joined(separator: "."))
        }
        if s.hasPrefix("gpt") {
            let p = raw.split(separator: "-").map(String.init)
            var out = p[0].uppercased()                       // GPT
            if p.count >= 2 { out += "-" + p[1] }             // GPT-5.3
            if p.count >= 3 { out += " " + p.dropFirst(2).map { $0.capitalized }.joined(separator: " ") }
            return out                                        // GPT-5.3 Codex / GPT-5.1 Codex Max
        }
        if s.contains("gemini") {
            let p = raw.split(separator: "-").map(String.init)
            if p.count >= 3 { return "Gemini \(p[1]) \(p[2].capitalized)" }
            return "Gemini"
        }
        if s.hasPrefix("gemma") {
            let rest = raw.dropFirst(5).drop(while: { $0 == "-" })
            return rest.isEmpty ? "Gemma" : "Gemma " + rest.replacingOccurrences(of: "-", with: " ")
        }
        if s.hasPrefix("o1") || s.hasPrefix("o3") || s.hasPrefix("o4") { return "OpenAI " + raw }
        if s.contains("deepseek") { return raw.replacingOccurrences(of: "deepseek", with: "DeepSeek") }
        if s.contains("qwen") { return raw.capitalized }
        if s.contains("kimi") { return raw.capitalized }
        if s.contains("glm") { return raw.uppercased() }
        if s.contains("llama") { return raw.capitalized }
        return String(raw.prefix(24))
    }

    /// Vendor tint for a pretty label — the base hue; modelShare then varies brightness so sibling
    /// versions (GPT-5.2 vs GPT-5.3 Codex) stay distinguishable within one vendor.
    static func vendorColor(_ label: String) -> Color {
        if label.hasPrefix("Claude") {
            if label.contains("Opus") { return V.coral }
            if label.contains("Sonnet") { return V.amber }
            if label.contains("Haiku") { return V.rose }
            if label.contains("Fable") { return V.violet }
            return V.coral
        }
        if label.hasPrefix("GPT") || label.hasPrefix("OpenAI") { return V.teal }
        if label.hasPrefix("Gemini") { return V.sky }
        if label.hasPrefix("Gemma") { return V.mint }
        if label == "其他" { return .gray }
        return V.indigo
    }

}

/// High-contrast qualitative palette for many-category charts (donut/bars). Ordered so that
/// adjacent ranks — which end up next to each other — are maximally different hues, giving each
/// slice a clearly distinct color rather than shades of one vendor tint.
enum ChartColors {
    static let seq: [Color] = [
        V.teal, V.coral, V.violet, V.amber, V.sky, V.rose, V.mint, V.indigo,
        Color(red: 0.56, green: 0.82, blue: 0.29),   // lime
        Color(red: 0.98, green: 0.55, blue: 0.20),   // orange
        Color(red: 0.85, green: 0.36, blue: 0.86),   // magenta
        Color(red: 0.36, green: 0.60, blue: 0.96),   // periwinkle
        Color(red: 0.96, green: 0.82, blue: 0.24),   // gold
        Color(red: 0.28, green: 0.78, blue: 0.86),   // cyan
    ]
    static func at(_ i: Int) -> Color { seq[((i % seq.count) + seq.count) % seq.count] }
}

// MARK: - Sessions

struct SessionRecord: Codable, Identifiable, Hashable {
    var id: String
    var agent: AgentKind
    var filePath: String
    var projectPath: String
    var gitBranch: String?
    var title: String
    var startedAt: Date
    var endedAt: Date
    var userMessages: Int
    var assistantMessages: Int
    var inputTokens: Int
    var outputTokens: Int
    /// Total tokens processed = input + output + cache reads + cache creation.
    /// For agent sessions this dwarfs output alone (context is re-read from cache each turn),
    /// and is the number that matches "this conversation is huge" intuition.
    var totalTokens: Int
    var tokensEstimated: Bool
    var models: [String]
    var toolCounts: [String: Int]
    var bashCommands: [String]
    var filesTouched: [String]
    var userPrompts: [String]
    var isSubagent: Bool
    var cliVersion: String?
    var summary: String?

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    var messageCount: Int { userMessages + assistantMessages }

    var projectName: String {
        let name = (projectPath as NSString).lastPathComponent
        return name.isEmpty ? projectPath : name
    }

    /// Sessions with no real browsing value: Vitrine's own AI-helper calls (summary / distill /
    /// insight, logged when they run through `claude -p`) and trivially short or aborted runs.
    /// Hidden by default in browse lists & search — but NEVER excluded from aggregates/stats.
    var isLowSignal: Bool {
        let markers = ["AI 编程会话总结器", "技能蒸馏器", "项目考古学家",
                       "SKILL.md 全文", "Generate metadata", "vitrine-briefing"]
        let hay = title + " " + (userPrompts.first ?? "")
        if markers.contains(where: { hay.contains($0) }) { return true }
        if messageCount <= 2 && totalTokens < 2000 { return true }
        return false
    }

    /// Three-tier quality for browsing. noise = low-signal (hidden by default everywhere);
    /// premium = substantive real work; standard = the rest. Recent-sessions prefers premium.
    enum QualityTier: Int { case noise = 0, standard = 1, premium = 2 }
    var qualityTier: QualityTier {
        if isLowSignal { return .noise }
        let substantive = messageCount >= 6 || totalTokens > 200_000
            || filesTouched.count >= 3 || bashCommands.count >= 5
        return substantive ? .premium : .standard
    }

    /// The raw title is unusable for browsing (empty / "（无标题会话）" / too short / a helper call).
    var hasWeakTitle: Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == "（无标题会话）" || t.count < 4 { return true }
        return isLowSignal
    }

    /// A structured, human-legible fallback built from what the session actually did —
    /// "<project> · <intent-or-activity>". Instant, deterministic, and never overwrites `title`.
    var heuristicTitle: String {
        if let p = userPrompts.first(where: { $0.count >= 8 }) {
            return projectName + " · " + SessionRecord.condense(p, 24)
        }
        return projectName + " · " + activityPhrase
    }

    /// Phase/activity inferred from structure when there's no usable prompt.
    private var activityPhrase: String {
        if let f = filesTouched.first {
            let base = (f as NSString).lastPathComponent
            return filesTouched.count > 1 ? "改动 \(base) 等 \(filesTouched.count) 文件" : "改动 \(base)"
        }
        if let c = bashCommands.first(where: { !$0.isEmpty }) {
            let verb = c.split(separator: " ").first.map(String.init) ?? "命令"
            return bashCommands.count > 1 ? "运行 \(verb) 等 \(bashCommands.count) 条命令" : "运行 \(verb)"
        }
        let reads = (toolCounts["Read"] ?? 0) + (toolCounts["Grep"] ?? 0) + (toolCounts["Glob"] ?? 0)
        if reads > 0 { return "查阅代码" }
        return "\(messageCount) 轮对话"
    }

    static func condense(_ s: String, _ n: Int) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.count > n ? String(t.prefix(n)) + "…" : t
    }
}

// MARK: - Projects

struct ProjectAggregate: Identifiable, Hashable {
    var path: String
    var sessions: [SessionRecord]   // sorted by startedAt ascending

    var id: String { path }
    var name: String {
        let n = (path as NSString).lastPathComponent
        return n.isEmpty ? path : n
    }

    var agents: [AgentKind] {
        var seen = Set<AgentKind>(), out: [AgentKind] = []
        for s in sessions where !seen.contains(s.agent) { seen.insert(s.agent); out.append(s.agent) }
        return out
    }

    var firstActivity: Date { sessions.first?.startedAt ?? .distantPast }
    var lastActivity: Date { sessions.map(\.endedAt).max() ?? .distantPast }
    var totalMessages: Int { sessions.reduce(0) { $0 + $1.messageCount } }
    var totalOutputTokens: Int { sessions.reduce(0) { $0 + $1.outputTokens } }
    var totalTokens: Int { sessions.reduce(0) { $0 + $1.totalTokens } }

    /// Distinct calendar days with at least one session — the "non-contiguous contribution" signal.
    var activeDays: Int {
        Set(sessions.map { Calendar.current.startOfDay(for: $0.startedAt) }).count
    }

    /// Calendar span from first to last activity, in days.
    var spanDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: firstActivity, to: lastActivity).day.map { $0 + 1 } ?? 1)
    }

    /// Share of messages per agent, for composition views.
    var agentShare: [(agent: AgentKind, messages: Int)] {
        var acc: [AgentKind: Int] = [:]
        for s in sessions { acc[s.agent, default: 0] += s.messageCount }
        return acc.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}

// MARK: - Project AI insight (secondary, non-destructive layer over static analysis)

struct InsightMilestone: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: String       // "2026-04" etc, model-provided label
    var title: String
    var detail: String

    enum CodingKeys: String, CodingKey { case date, title, detail }
}

struct ProjectInsight: Codable, Hashable {
    var projectPath: String
    var generatedAt: Date
    var model: String
    var overview: String
    var timeline: [InsightMilestone]
    var highlights: [String]
}

// MARK: - Search

struct SearchHit: Identifiable, Hashable {
    var id: String { sessionId + snippet }
    var sessionId: String
    var snippet: String
    var rank: Double
}

// MARK: - Memory

enum MemorySourceKind: String, CaseIterable {
    case claudeGlobal, claudeProjectMemory, projectClaudeMd, projectAgentsMd
    case codexGlobal, geminiGlobal, cursorRules, windsurfRules, copilotInstructions

    var display: String {
        switch self {
        case .claudeGlobal: "Claude 全局 CLAUDE.md"
        case .claudeProjectMemory: "Claude 项目记忆库"
        case .projectClaudeMd: "项目 CLAUDE.md"
        case .projectAgentsMd: "项目 AGENTS.md"
        case .codexGlobal: "Codex 全局 AGENTS.md"
        case .geminiGlobal: "Gemini 全局 GEMINI.md"
        case .cursorRules: ".cursorrules"
        case .windsurfRules: ".windsurfrules"
        case .copilotInstructions: "Copilot instructions"
        }
    }

    var agent: AgentKind {
        switch self {
        case .claudeGlobal, .claudeProjectMemory, .projectClaudeMd: .claude
        case .codexGlobal, .projectAgentsMd: .codex
        case .geminiGlobal: .gemini
        case .cursorRules: .cursor
        case .windsurfRules: .windsurf
        case .copilotInstructions: .other
        }
    }
}

struct MemorySource: Identifiable, Hashable {
    var id: String { path }
    var kind: MemorySourceKind
    var path: String
    var projectPath: String?    // nil for globals
    var sizeBytes: Int
    var modifiedAt: Date

    var title: String {
        if let p = projectPath { return "\((p as NSString).lastPathComponent) · \(kind.display)" }
        return kind.display
    }
}

struct MemoryItem: Identifiable, Hashable {
    var id: String
    var sourcePath: String
    var sourceKind: MemorySourceKind
    var name: String        // slug or heading
    var type: String        // user | feedback | project | reference | section
    var body: String        // markdown body (without frontmatter)
}

// MARK: - Distillery

struct SkillEvidence: Hashable {
    var projectPath: String
    var sessionCount: Int
    var topCommands: [(String, Int)]
    var topTools: [(String, Int)]
    var fileExtensions: [(String, Int)]
    var conventions: [String]
    var recurringAsks: [String]

    static func == (l: SkillEvidence, r: SkillEvidence) -> Bool { l.projectPath == r.projectPath }
    func hash(into h: inout Hasher) { h.combine(projectPath) }
}

struct DistilledSkill: Identifiable {
    var id = UUID()
    var name: String
    var description: String
    var body: String        // full SKILL.md content
    var origin: String      // "heuristic" | "ai"
}

/// What an AI distillation should emphasize — steers the SKILL.md toward one facet or covers all.
enum DistillFocus: String, CaseIterable, Identifiable {
    case all, conventions, commands, workflow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "全面"
        case .conventions: "规范"
        case .commands: "命令"
        case .workflow: "工作流"
        }
    }
    var directive: String {
        switch self {
        case .all: ""
        case .conventions: " 重点提炼开发规范、代码约定与项目纪律，弱化零散命令。"
        case .commands: " 重点提炼高频命令、脚本与可复用的操作步骤，给出可直接执行的片段。"
        case .workflow: " 重点提炼端到端的工作流程、任务拆解与多 Agent 协作范式。"
        }
    }
}

enum InjectionTarget: String, CaseIterable, Identifiable {
    case claudeSkills, projectClaudeDir
    case codexAgentsMd, geminiMd
    case projectAgentsMd, projectCursorRules, projectWindsurfRules
    var id: String { rawValue }

    var display: String {
        switch self {
        case .claudeSkills: "Claude 全局技能 · ~/.claude/skills/"
        case .projectClaudeDir: "项目技能 · .claude/skills/"
        case .codexAgentsMd: "Codex 全局 · ~/.codex/AGENTS.md"
        case .geminiMd: "Gemini 全局 · ~/.gemini/GEMINI.md"
        case .projectAgentsMd: "项目 AGENTS.md · Codex/opencode"
        case .projectCursorRules: "项目 .cursorrules · Cursor"
        case .projectWindsurfRules: "项目 .windsurfrules · Windsurf"
        }
    }

    /// Which agent this target feeds — drives the icon/tint in the picker.
    var agent: AgentKind {
        switch self {
        case .claudeSkills, .projectClaudeDir: .claude
        case .codexAgentsMd, .projectAgentsMd: .codex
        case .geminiMd: .gemini
        case .projectCursorRules: .cursor
        case .projectWindsurfRules: .windsurf
        }
    }

    /// Skill-directory style (Claude) vs. markdown-append style (everything else).
    var isSkillDir: Bool { self == .claudeSkills || self == .projectClaudeDir }
    var needsProject: Bool {
        self == .projectClaudeDir || self == .projectAgentsMd
            || self == .projectCursorRules || self == .projectWindsurfRules
    }
}

// MARK: - Dispatch

struct CLITool: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var path: String
    var agent: AgentKind
}
