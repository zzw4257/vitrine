import SwiftUI
import Observation

@Observable
final class AppStore {
    // Scan state
    var scanning = false
    var progress: Double = 0
    var status = ""
    var lastScan: Date?

    // Data
    var allSessions: [SessionRecord] = []
    var projects: [ProjectAggregate] = []
    var cliTools: [CLITool] = []
    var memorySources: [MemorySource] = []
    var projectSourcesLoaded = false
    var indexReady = false
    var includeSubagents = false { didSet { rebuildProjects() } }
    /// When false (default) browse lists & search hide low-signal sessions (Vitrine's own helper
    /// calls, trivial runs). Aggregates are unaffected. Resets to hidden each launch.
    var showLowSignal = false

    var hiddenLowSignalCount: Int { sessions.lazy.filter(\.isLowSignal).count }

    // AI summaries, persisted separately from the scan cache
    var summaries: [String: String] = [:]

    // Per-project AI insights (overview + timeline) — a secondary layer, cached per path
    var insights: [String: ProjectInsight] = [:]

    // AI configuration (provider / endpoint / model) — hindsight-style
    let ai = AISettings()
    // Local inference engine (Ollama + llama.cpp) state
    let localEngine = LocalEngineModel()

    @ObservationIgnored var searchIndex: SearchIndex?
    @ObservationIgnored private var byId: [String: SessionRecord] = [:]

    var claudePath: String? { cliTools.first { $0.name == "claude" }?.path }
    /// AI is usable if a cloud endpoint is configured, or the local claude CLI is present.
    var aiAvailable: Bool {
        ai.isLocalClaude ? (claudePath != nil) : ai.configured
    }

    var sessions: [SessionRecord] {
        includeSubagents ? allSessions : allSessions.filter { !$0.isSubagent }
    }

    func session(_ id: String) -> SessionRecord? { byId[id] }

    /// User-initiated: scan in-repo rule files (may prompt for Documents access once).
    @MainActor
    func loadProjectMemorySources() {
        let extra = MemoryManager.discoverProjectSources(projects: projects)
        var merged = memorySources.filter { $0.projectPath == nil || $0.kind == .claudeProjectMemory }
        merged.append(contentsOf: extra)
        memorySources = merged.sorted { $0.modifiedAt > $1.modifiedAt }
        projectSourcesLoaded = true
    }

    func summary(for s: SessionRecord) -> String {
        summaries[s.id] ?? Summarizer.heuristic(s)
    }

    // MARK: Lifecycle

    @MainActor
    func refresh() async {
        guard !scanning else { return }
        scanning = true
        progress = 0
        status = "发现会话文件…"
        loadSummaries()
        loadInsights()

        // Phase 1: cache hits + opencode metadata appear immediately.
        let prepared = await Task.detached(priority: .userInitiated) {
            ScanEngine.prepare()
        }.value
        let opencode = await Task.detached(priority: .utility) {
            OpencodeScanner.scanAll()
        }.value
        setSessions(prepared.cachedRecords + opencode)
        status = prepared.pending.isEmpty
            ? "共 \(allSessions.count) 个会话"
            : "缓存命中 \(prepared.cachedRecords.count) · 解析 \(prepared.pending.count) 个新会话…"

        // Phase 2: stream newly parsed files into the UI as they finish.
        let store = self
        await ScanEngine.parse(prepared.pending, cache: prepared.cache) { p, msg in
            Task { @MainActor in
                store.progress = p
                store.status = msg
            }
        } onBatch: { batch in
            Task { @MainActor in
                store.setSessions(store.allSessions + batch)
            }
        }

        // Late, path-dependent scanners: Gemini (SHA-256 project dirs), Cursor (relational
        // summary DB) and Windsurf (encrypted transcripts → code-tracker footprint). All resolve
        // their projects against the paths every other scanner has now surfaced.
        let knownPaths = allSessions.map(\.projectPath)
        let extra = await Task.detached(priority: .utility) { () -> [SessionRecord] in
            GeminiScanner.scanAll(knownPaths: knownPaths)
                + CursorScanner.scanAll(knownPaths: knownPaths)
                + WindsurfScanner.scanAll(knownPaths: knownPaths)
        }.value
        if !extra.isEmpty { setSessions(allSessions + extra) }

        status = "构建全文索引…"
        let indexPath = ScanEngine.supportDir.appendingPathComponent("search-v1.db").path
        let toIndex = allSessions
        let summarySnapshot = summaries
        let builtIndex = await Task.detached(priority: .userInitiated) { () -> SearchIndex? in
            let idx = SearchIndex(path: indexPath)
            var enriched = toIndex
            for i in enriched.indices {
                if let s = summarySnapshot[enriched[i].id] { enriched[i].summary = s }
            }
            idx?.rebuild(enriched)
            return idx
        }.value
        searchIndex = builtIndex
        indexReady = builtIndex != nil

        cliTools = CLI.detectTools()
        memorySources = MemoryManager.discoverGlobalSources()
        lastScan = Date()
        status = "共 \(allSessions.count) 个会话 · \(projects.count) 个项目"
        scanning = false
    }

    @MainActor
    private func setSessions(_ records: [SessionRecord]) {
        allSessions = records.sorted { $0.startedAt > $1.startedAt }
        byId = Dictionary(allSessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        rebuildProjects()
    }

    func rebuildProjects() {
        let grouped = Dictionary(grouping: sessions, by: \.projectPath)
        projects = grouped.map { path, recs in
            ProjectAggregate(path: path, sessions: recs.sorted { $0.startedAt < $1.startedAt })
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: AI summaries

    private var summariesURL: URL { ScanEngine.supportDir.appendingPathComponent("summaries.json") }

    func loadSummaries() {
        guard summaries.isEmpty,
              let data = try? Data(contentsOf: summariesURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        summaries = dict
    }

    func saveSummaries() {
        if let data = try? JSONEncoder().encode(summaries) {
            try? data.write(to: summariesURL, options: .atomic)
        }
    }

    @MainActor
    func generateAISummary(for s: SessionRecord) async throws {
        let cfg = ai.snapshot()
        let text = try await AIClient.chat(
            cfg,
            system: "你是一个 AI 编程会话总结器。用中文输出两三句话的简洁总结，不要任何前后缀。",
            user: Summarizer.aiPrompt(for: s), maxTokens: 400)
        summaries[s.id] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        saveSummaries()
    }

    // Batch summarization
    var batchSummarizing = false
    var batchDone = 0
    var batchTotal = 0
    @ObservationIgnored private var batchCancel = false

    func cancelBatch() { batchCancel = true }

    /// Summarize all not-yet-summarized sessions (optionally forcing all), a few at a time.
    @MainActor
    func batchSummarize(_ sessions: [SessionRecord], force: Bool = false) async {
        guard !batchSummarizing else { return }
        let targets = force ? sessions : sessions.filter { summaries[$0.id] == nil }
        guard !targets.isEmpty else { return }
        batchSummarizing = true
        batchCancel = false
        batchDone = 0
        batchTotal = targets.count
        let cfg = ai.snapshot()

        // Small concurrency pool (cloud rate limits + local single-GPU both prefer modest fan-out).
        let pool = 3
        var iterator = targets.makeIterator()
        await withTaskGroup(of: (String, String)?.self) { group in
            func addNext() {
                guard !batchCancel, let s = iterator.next() else { return }
                group.addTask {
                    let text = try? await AIClient.chat(
                        cfg,
                        system: "你是一个 AI 编程会话总结器。用中文输出两三句话的简洁总结，不要任何前后缀。",
                        user: Summarizer.aiPrompt(for: s), maxTokens: 400)
                    guard let text, !text.isEmpty else { return nil }
                    return (s.id, text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            for _ in 0..<pool { addNext() }
            while let result = await group.next() {
                if let (id, text) = result { summaries[id] = text }
                batchDone += 1
                if !batchCancel { addNext() }
            }
        }
        saveSummaries()
        batchSummarizing = false
    }

    // MARK: Project insights

    private var insightsURL: URL { ScanEngine.supportDir.appendingPathComponent("insights.json") }

    func loadInsights() {
        guard insights.isEmpty,
              let data = try? Data(contentsOf: insightsURL),
              let dict = try? JSONDecoder().decode([String: ProjectInsight].self, from: data) else { return }
        insights = dict
    }

    private func saveInsights() {
        if let data = try? JSONEncoder().encode(insights) {
            try? data.write(to: insightsURL, options: .atomic)
        }
    }

    /// Generate a secondary AI insight (overview + milestone timeline) from the project's
    /// STATIC facts. Does not touch or replace the static analysis — purely additive.
    @MainActor
    func generateInsight(for project: ProjectAggregate) async throws {
        let cfg = ai.snapshot()
        let facts = Summarizer.projectFacts(project, summaries: summaries)
        let raw = try await AIClient.chat(
            cfg,
            system: Summarizer.insightSystemPrompt,
            user: facts, maxTokens: 2200, timeout: 200)
        let parsed = try Summarizer.parseInsight(raw, project: project, model: cfg.model.isEmpty ? cfg.providerID : cfg.model)
        insights[project.path] = parsed
        saveInsights()
    }
}

// MARK: - Shared aggregation helpers

extension Array where Element == SessionRecord {
    /// Message activity bucketed per calendar day.
    func dailyActivity() -> [Date: Int] {
        var out: [Date: Int] = [:]
        let cal = Calendar.current
        for s in self {
            out[cal.startOfDay(for: s.startedAt), default: 0] += Swift.max(1, s.messageCount)
        }
        return out
    }

    var totalOutputTokens: Int { reduce(0) { $0 + $1.outputTokens } }
    var totalTokens: Int { reduce(0) { $0 + $1.totalTokens } }
    var totalMessages: Int { reduce(0) { $0 + $1.messageCount } }

    /// Distribution of activity across model *families* (Opus/Sonnet/Gemini/GPT…), for the
    /// composition donut. A session's messages are split evenly across the models it used.
    /// Agent composition weighted by the chosen metric.
    func agentShare(by metric: ShareMetric) -> [(agent: AgentKind, messages: Int)] {
        var acc: [AgentKind: Int] = [:]
        for s in self { acc[s.agent, default: 0] += metric.weight(s) }
        return acc.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    func modelShare(by metric: ShareMetric = .messages) -> [(label: String, value: Int, color: Color)] {
        var acc: [String: Double] = [:]
        for s in self where !s.models.isEmpty {
            let labels = s.models.map(ModelInfo.label).filter { !$0.isEmpty }
            guard !labels.isEmpty else { continue }
            let w = Double(metric.weight(s)) / Double(labels.count)
            guard w > 0 else { continue }
            for l in labels { acc[l, default: 0] += w }
        }
        // Show the SPECIFIC models, ranked. Keep a generous head so real versions stay visible;
        // fold only the far tail into "其他".
        let ranked = acc.sorted { $0.value > $1.value }
        let maxShown = 12
        let head = ranked.prefix(maxShown)
        let tail = ranked.dropFirst(maxShown).reduce(0.0) { $0 + $1.value }

        // Color: distinct qualitative palette by rank — maximal separation between slices.
        var out: [(String, Int, Color)] = head.enumerated().map { i, kv in
            (kv.key, Int(kv.value.rounded()), ChartColors.at(i))
        }
        if tail > 0 { out.append(("其他", Int(tail.rounded()), .gray)) }
        return out
    }
}
