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

    // Smart titles — a NON-destructive title layer (raw `title` is always preserved).
    // AI-generated entries live here (persisted); heuristic titles are computed on the fly.
    var smartTitles: [String: String] = [:]
    // apply smart/heuristic to ALL sessions (not only weak-titled ones); persisted
    var useSmartTitles = UserDefaults.standard.bool(forKey: "vitrine.useSmartTitles") {
        didSet { UserDefaults.standard.set(useSmartTitles, forKey: "vitrine.useSmartTitles") }
    }
    // after each scan, quietly AI-title recent weak-titled sessions in the background; persisted
    var autoSmartTitles = UserDefaults.standard.bool(forKey: "vitrine.autoSmartTitles") {
        didSet { UserDefaults.standard.set(autoSmartTitles, forKey: "vitrine.autoSmartTitles") }
    }
    // AI generation scope: weak-titled only (cheap, default) vs. every non-noise session
    // (catches long-but-uninformative raw titles that `hasWeakTitle` doesn't flag); persisted
    var retitleAllSessions = UserDefaults.standard.bool(forKey: "vitrine.retitleAllSessions") {
        didSet { UserDefaults.standard.set(retitleAllSessions, forKey: "vitrine.retitleAllSessions") }
    }
    // Per-session fine-grained override of the title source, set from the session detail sheet.
    // Takes priority over every global default; persisted.
    var titleOverrides: [String: TitleOverride] = [:]

    enum TitleOverride: String, Codable { case raw, smart }

    /// A session whose AI title is being generated right now (drives the row shimmer).
    func titlePending(_ s: SessionRecord) -> Bool {
        titlingBusy && smartTitles[s.id] == nil && s.qualityTier != .noise
            && (s.hasWeakTitle || retitleAllSessions)
    }

    /// The title to show for browsing. Priority: an explicit per-session choice → AI smart title
    /// → heuristic (for weak titles, or when smart mode is on) → the raw title. Never mutates
    /// the SessionRecord.
    func displayTitle(_ s: SessionRecord) -> String {
        switch titleOverrides[s.id] {
        case .raw: return s.title
        case .smart: return smartTitles[s.id] ?? s.heuristicTitle
        case nil: break
        }
        if let ai = smartTitles[s.id], !ai.isEmpty { return ai }
        if useSmartTitles || s.hasWeakTitle { return s.heuristicTitle }
        return s.title
    }

    /// Explicitly pin this session's title to the raw text or the smart (AI/heuristic) text,
    /// overriding whatever the global toggles would otherwise pick. Pass nil to clear back to default.
    func setTitleOverride(_ choice: TitleOverride?, for id: String) {
        titleOverrides[id] = choice
        saveTitleOverrides()
    }

    // Per-project AI insights (overview + timeline) — a secondary layer, cached per path
    var insights: [String: ProjectInsight] = [:]

    /// Manual "this session's real work happened in <sub-path>" tag — for monorepos where the
    /// CLI was invoked from a parent directory but the actual scope was one package/app inside
    /// it. Purely additive and user-entered (never inferred); feeds the search index so browsing
    /// or searching that sub-path surfaces the session too. Keyed by session id; persisted.
    var scopeTags: [String: String] = [:]

    /// Conversations pinned from inside a running CLI session via the installed vitrine-pin
    /// skill/command (see PinKit.swift) — shared with those scripts through pins.json, keyed by
    /// transcript file path. Loaded read-only here except when the user renames/unpins in-app.
    var pins: [String: PinRecord] = [:]
    /// Terser, pinned-view-only AI summaries — see `generatePinSummary`. Keyed by file path (not
    /// session id) so a pin summary survives even before its transcript has been scanned.
    var pinSummaries: [String: String] = [:]

    // AI configuration (provider / endpoint / model) — hindsight-style
    let ai = AISettings()
    // Local inference engine (Ollama + llama.cpp) state
    let localEngine = LocalEngineModel()
    // Multi-device GitLab sync configuration (device identity, remote, token) — see DeviceSync.swift
    let sync = SyncSettings()

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
        loadSmartTitles()
        loadTitleOverrides()
        loadScopeTags()
        loadPins()
        loadPinSummaries()

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
        let scopeSnapshot = scopeTags
        let builtIndex = await Task.detached(priority: .userInitiated) { () -> SearchIndex? in
            let idx = SearchIndex(path: indexPath)
            var enriched = toIndex
            for i in enriched.indices {
                if let s = summarySnapshot[enriched[i].id] { enriched[i].summary = s }
                // Fold the manual working-scope tag into the indexed text so searching a
                // monorepo sub-path (e.g. "apps/foo") surfaces sessions actually scoped there,
                // even though their projectPath is the checkout root.
                if let scope = scopeSnapshot[enriched[i].id], !scope.isEmpty {
                    enriched[i].summary = [enriched[i].summary, "工作范围：\(scope)"]
                        .compactMap { $0 }.joined(separator: "\n")
                }
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

        // Quietly upgrade recent weak titles in the background, if the user opted in.
        if autoSmartTitles && aiAvailable {
            Task { await generateSmartTitles(auto: true) }
        }
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
            user: Summarizer.aiPrompt(for: s), maxTokens: 400, model: cfg.fastModel)
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
                        user: Summarizer.aiPrompt(for: s), maxTokens: 400, model: cfg.fastModel)
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

    // MARK: Smart titles (non-destructive AI title layer)

    private var smartTitlesURL: URL { ScanEngine.supportDir.appendingPathComponent("smart-titles.json") }

    func loadSmartTitles() {
        guard smartTitles.isEmpty,
              let data = try? Data(contentsOf: smartTitlesURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        smartTitles = dict
    }
    private func saveSmartTitles() {
        if let data = try? JSONEncoder().encode(smartTitles) {
            try? data.write(to: smartTitlesURL, options: .atomic)
        }
    }

    private var titleOverridesURL: URL { ScanEngine.supportDir.appendingPathComponent("title-overrides.json") }

    func loadTitleOverrides() {
        guard titleOverrides.isEmpty,
              let data = try? Data(contentsOf: titleOverridesURL),
              let dict = try? JSONDecoder().decode([String: TitleOverride].self, from: data) else { return }
        titleOverrides = dict
    }
    private func saveTitleOverrides() {
        if let data = try? JSONEncoder().encode(titleOverrides) {
            try? data.write(to: titleOverridesURL, options: .atomic)
        }
    }

    var titlingBusy = false
    var titleDone = 0
    var titleTotal = 0
    @ObservationIgnored private var titleCancel = false
    func cancelTitling() { titleCancel = true }

    /// A session qualifies for AI (re)titling when it's not noise, has real content to title from,
    /// and either has a weak raw title or the user opted into retitling every session.
    private func qualifiesForRetitle(_ s: SessionRecord) -> Bool {
        guard s.qualityTier != .noise, s.hasTitleSignal else { return false }
        return s.hasWeakTitle || retitleAllSessions
    }

    /// Count of sessions that would benefit from an AI title right now (not yet done).
    var pendingTitleCount: Int {
        sessions.lazy.filter { self.qualifiesForRetitle($0) && self.smartTitles[$0.id] == nil }.count
    }

    /// Sessions permanently stuck on the heuristic fallback because there's nothing concrete to
    /// title with (no substantive prompts, no files, no commands) — shown in Settings so the gap
    /// reads as "honest, nothing to say" rather than "the feature is broken".
    var noSignalTitleCount: Int {
        sessions.lazy.filter { $0.qualityTier != .noise && $0.hasWeakTitle && !$0.hasTitleSignal }.count
    }

    /// Incrementally generate AI smart titles for qualifying sessions without one (see
    /// `qualifiesForRetitle`). `auto` (post-scan background pass) caps to the most recent few to
    /// stay cheap. Cached + persisted; never touches raw titles. Small concurrency pool.
    @MainActor
    func generateSmartTitles(force: Bool = false, auto: Bool = false) async {
        guard !titlingBusy, aiAvailable else { return }
        if force {
            // Drop stale titles for sessions that no longer qualify (contentless / noise) so they
            // fall back to the honest heuristic instead of keeping an old hallucinated title.
            let valid = Set(allSessions.filter { $0.hasTitleSignal && $0.qualityTier != .noise }.map(\.id))
            let pruned = smartTitles.filter { valid.contains($0.key) }
            if pruned.count != smartTitles.count { smartTitles = pruned; saveSmartTitles() }
        }
        var targets = sessions.filter { s in
            guard qualifiesForRetitle(s) else { return false }
            return force || smartTitles[s.id] == nil                             // force also refreshes cached
        }
        if auto { targets = Array(targets.prefix(60)) }                // sessions are recent-first
        guard !targets.isEmpty else { return }
        titlingBusy = true; titleCancel = false; titleDone = 0; titleTotal = targets.count
        let cfg = ai.snapshot()

        var iterator = targets.makeIterator()
        await withTaskGroup(of: (String, String)?.self) { group in
            func addNext() {
                guard !titleCancel, let s = iterator.next() else { return }
                let facts = Self.titleFacts(s, summary: summaries[s.id])
                group.addTask {
                    let out = try? await AIClient.chat(
                        cfg,
                        system: Self.titleSystemPrompt,
                        user: facts, maxTokens: 80, timeout: 60, model: cfg.fastModel)
                    guard let out, !out.isEmpty else { return nil }
                    var clean = out.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " ")
                    clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "「」『』\"'“”。. "))
                    guard !clean.isEmpty else { return nil }
                    return (s.id, String(clean.prefix(40)))
                }
            }
            for _ in 0..<3 { addNext() }
            while let r = await group.next() {
                if let (id, t) = r { smartTitles[id] = t }
                titleDone += 1
                if !titleCancel { addNext() }
            }
        }
        saveSmartTitles()
        titlingBusy = false
    }

    /// Compact structured facts for the title model: project · phase-signals · intent.
    /// Facts for the title model, strongest signal first. An existing summary (real content) beats
    /// everything; then the actual asks; then the concrete files/commands touched.
    private static func titleFacts(_ s: SessionRecord, summary: String?) -> String {
        var lines = ["项目：\(s.projectName)"]
        if let sum = summary, !sum.isEmpty, !SessionRecord.looksLikeFailedSummary(sum) {
            lines.append("会话摘要（最可靠，优先据此提炼）：" + SessionRecord.condense(sum, 180))
        }
        let prompts = s.substantivePrompts.prefix(4).map { SessionRecord.condense($0, 90) }
        if !prompts.isEmpty { lines.append("用户实际提问：" + prompts.joined(separator: " ／ ")) }
        if !s.filesTouched.isEmpty {
            lines.append("改动文件：" + s.filesTouched.prefix(8).map { ($0 as NSString).lastPathComponent }.joined(separator: "、"))
        }
        if !s.bashCommands.isEmpty {
            lines.append("关键命令：" + s.bashCommands.prefix(5).map { String($0.prefix(50)) }.joined(separator: " ; "))
        }
        lines.append("规模：\(s.messageCount) 轮 · \(Fmt.tokens(s.totalTokens)) tokens")
        return lines.joined(separator: "\n")
    }

    /// Title prompt: few-shot + an explicit ban on the vague filler Haiku falls back to.
    static let titleSystemPrompt = """
    你为一次 AI 编程会话起一个精准的中文短标题，像给 Pull Request 起标题。
    - 格式「项目 · 要点」，总长 ≤16 字；「项目」尽量沿用给定的项目名。
    - 「要点」必须具体说清这次到底做了什么：具体功能 / 文件 / 问题 / 模块 / 决策。
    - 严禁空泛词：迭代、探索、优化、深度、持续、编程工作、开发、处理、相关、若干、初步、启动、就绪、确认。
    - 只输出标题本身，不带引号、不带解释、结尾不加标点。
    示例：
    MLsys · 修复 KV-cache 显存泄漏
    日历助手 · 接入本地 Whisper 语音
    GoPhish · 补全钓鱼邮件模板与追踪
    量化回测 · 定位 Sharpe 计算错误
    """

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

    // MARK: Working-scope tags (manual, non-destructive — see `scopeTags` doc comment)

    private var scopeTagsURL: URL { ScanEngine.supportDir.appendingPathComponent("scope-tags.json") }

    func loadScopeTags() {
        guard scopeTags.isEmpty,
              let data = try? Data(contentsOf: scopeTagsURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        scopeTags = dict
    }
    private func saveScopeTags() {
        if let data = try? JSONEncoder().encode(scopeTags) {
            try? data.write(to: scopeTagsURL, options: .atomic)
        }
    }

    /// Set (or clear, with an empty/whitespace string) the manual working-scope tag for a session.
    func setScopeTag(_ tag: String, for id: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { scopeTags.removeValue(forKey: id) } else { scopeTags[id] = trimmed }
        saveScopeTags()
    }

    // MARK: Multi-device sync

    /// This device's current aggregate snapshot — the ONLY thing a sync ever uploads. No prompts,
    /// no transcripts, no file paths beyond a project's display name.
    func currentDeviceSnapshot() -> DeviceSnapshot {
        let cost = sessions.totalEstimatedCost()
        var share: [String: Int] = [:]
        for (agent, n) in sessions.agentShare(by: .messages) { share[agent.rawValue] = n }
        return DeviceSnapshot(device: DeviceIdentity.current(), syncedAt: Date(),
                               sessionCount: sessions.count, projectCount: projects.count,
                               totalTokens: sessions.totalTokens, estimatedCostUSD: cost.usd,
                               agentShare: share)
    }

    @MainActor
    func syncNow() async {
        guard !sync.syncing else { return }
        sync.syncing = true
        sync.lastResult = nil
        do {
            let msg = try await GitSync.syncNow(remoteURL: sync.remoteURL, token: sync.token,
                                                 snapshot: currentDeviceSnapshot())
            sync.lastResult = (msg, false)
            sync.lastSyncAt = Date()
        } catch {
            sync.lastResult = (error.localizedDescription, true)
        }
        sync.syncing = false
    }

    // MARK: Pinned-view summaries — deliberately terser than the session-detail summary, since
    // the Pinned panel shows many at once and needs a subtitle, not a paragraph.

    private var pinSummariesURL: URL { ScanEngine.supportDir.appendingPathComponent("pin-summaries.json") }

    func loadPinSummaries() {
        guard pinSummaries.isEmpty,
              let data = try? Data(contentsOf: pinSummariesURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        pinSummaries = dict
    }
    private func savePinSummaries() {
        if let data = try? JSONEncoder().encode(pinSummaries) {
            try? data.write(to: pinSummariesURL, options: .atomic)
        }
    }

    @MainActor
    func generatePinSummary(for s: SessionRecord) async throws {
        let cfg = ai.snapshot()
        let text = try await AIClient.chat(
            cfg,
            system: "你为置顶列表写一句最精炼的中文副标题（≤18 字，一个短语，不成句、不带标点），"
                  + "概括这次会话做了什么，供一眼扫过时识别，而不是完整总结。",
            user: Summarizer.aiPrompt(for: s), maxTokens: 60, model: cfg.fastModel)
        pinSummaries[s.filePath] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        savePinSummaries()
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
