import Foundation
import AppKit

// MARK: - CLI runner

enum CLI {
    /// Known agent CLIs, detected by probing common install locations.
    static func detectTools() -> [CLITool] {
        let home = NSHomeDirectory()
        let candidates: [(String, AgentKind, [String])] = [
            ("claude",   .claude,   ["\(home)/.local/bin/claude", "/usr/local/bin/claude", "/opt/homebrew/bin/claude"]),
            ("codex",    .codex,    ["\(home)/.nvm/versions/node/v22.19.0/bin/codex", "/usr/local/bin/codex", "/opt/homebrew/bin/codex", "\(home)/.local/bin/codex"]),
            ("gemini",   .gemini,   ["/usr/local/bin/gemini", "/opt/homebrew/bin/gemini", "\(home)/.local/bin/gemini"]),
            ("cursor-agent", .cursor, ["\(home)/.local/bin/cursor-agent", "/usr/local/bin/cursor-agent", "/opt/homebrew/bin/cursor-agent"]),
            ("windsurf", .windsurf, ["\(home)/.codeium/windsurf/bin/windsurf", "/usr/local/bin/windsurf", "/opt/homebrew/bin/windsurf"]),
            ("opencode", .opencode, ["\(home)/.opencode/bin/opencode", "/opt/homebrew/bin/opencode"]),
            ("paseo",    .other,    ["\(home)/.local/bin/paseo", "/opt/homebrew/bin/paseo"]),
        ]
        var out: [CLITool] = []
        for (name, agent, paths) in candidates {
            if let p = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                out.append(CLITool(name: name, path: p, agent: agent))
            } else if let p = which(name) {
                out.append(CLITool(name: name, path: p, agent: agent))
            }
        }
        return out
    }

    /// Search common install dirs directly — no login shell (a login shell would source
    /// the user's rc files and could touch ~/Documents, wrongly attributing a TCC prompt to us).
    static func which(_ name: String) -> String? {
        let home = NSHomeDirectory()
        let dirs = [
            "\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin",
            "\(home)/.bun/bin", "\(home)/.deno/bin", "/usr/bin",
        ]
        for d in dirs {
            let candidate = "\(d)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        // Fall back to the inherited PATH, still without a login shell.
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for d in path.split(separator: ":") {
                let candidate = "\(d)/\(name)"
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return nil
    }

    /// Run `claude -p` headless; returns stdout. Throws on failure/timeout.
    static func runClaude(_ prompt: String, claudePath: String,
                          model: String = "claude-haiku-4-5-20251001",
                          timeout: TimeInterval = 120) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: claudePath)
                p.arguments = ["-p", prompt, "--output-format", "text", "--model", model]
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "\(NSHomeDirectory())/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
                p.environment = env
                let outPipe = Pipe(), errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError = errPipe
                do { try p.run() } catch { cont.resume(throwing: error); return }

                let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                timer.cancel()

                let out = String(data: outData, encoding: .utf8) ?? ""
                if p.terminationStatus == 0 && !out.trimmingCharacters(in: .whitespaces).isEmpty {
                    cont.resume(returning: out)
                } else {
                    let err = String(data: errData, encoding: .utf8) ?? "claude 退出码 \(p.terminationStatus)"
                    cont.resume(throwing: NSError(domain: "Vitrine", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: String(err.prefix(300))]))
                }
            }
        }
    }

    /// Open Terminal.app in `cwd` and run `command`.
    static func launchInTerminal(command: String, cwd: String) {
        let full = "cd \(shellQuote(cwd)) && \(command)"
        let escaped = full
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func copyToPasteboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

// MARK: - Summarizer

enum Summarizer {
    /// Instant, offline summary from scan metadata.
    static func heuristic(_ r: SessionRecord) -> String {
        var parts: [String] = []
        parts.append("围绕「\(r.title)」展开，共 \(r.userMessages) 轮提问、\(r.assistantMessages) 次回复。")
        let topTools = r.toolCounts.sorted { $0.value > $1.value }.prefix(3)
        if !topTools.isEmpty {
            parts.append("主要工具：" + topTools.map { "\($0.key)×\($0.value)" }.joined(separator: "、") + "。")
        }
        if !r.filesTouched.isEmpty {
            parts.append("涉及 \(r.filesTouched.count) 个文件。")
        }
        return parts.joined(separator: " ")
    }

    static func aiPrompt(for r: SessionRecord) -> String {
        let prompts = r.userPrompts.prefix(12).enumerated()
            .map { "\($0.offset + 1). \($0.element.prefix(200))" }
            .joined(separator: "\n")
        return """
        以下是一次 AI 编程会话中用户的关键请求序列（项目：\(r.projectName)，工具：\(r.agent.display)）。\
        请用中文输出两三句话的会话总结：先说这次会话完成了什么，再说涉及的关键模块/技术点。不要输出任何前后缀说明。

        \(prompts)
        """
    }

    // MARK: Project insight (secondary layer)

    static let insightSystemPrompt = """
    你是一个「项目考古学家」。下面给你的是某个软件项目里跨多个 AI Agent 会话的静态事实（时间、Agent、\
    会话标题、关键提问、命令、规范）。请基于这些事实，输出一个 JSON 对象概述该项目的演进，帮助后来者快速理解。

    严格只输出 JSON，不要任何解释或代码块围栏。结构：
    {
      "overview": "两三句话的项目概述：它在做什么、当前进展到哪、多个 Agent 如何协作",
      "timeline": [
        {"date": "YYYY-MM 或阶段名", "title": "阶段标题", "detail": "这一阶段发生了什么，一两句"}
      ],
      "highlights": ["值得注意的技术点或模式，3-6 条"]
    }
    timeline 按时间正序，聚合成 3-7 个有意义的阶段（不要每个会话一条）。用中文。
    """

    static func projectFacts(_ p: ProjectAggregate, summaries: [String: String]) -> String {
        var md = "# 项目：\(p.name)\n路径：\(p.path)\n"
        md += "跨度：\(Fmt.day(p.firstActivity)) → \(Fmt.day(p.lastActivity))，\(p.sessions.count) 个会话，"
        md += "参与 Agent：\(p.agents.map(\.display).joined(separator: "、"))\n\n## 会话时间线（旧→新）\n"
        for s in p.sessions.sorted(by: { $0.startedAt < $1.startedAt }).prefix(40) {
            md += "- \(Fmt.day(s.startedAt)) [\(s.agent.display)] \(s.title)"
            if let sum = summaries[s.id] { md += " —— \(sum.replacingOccurrences(of: "\n", with: " ").prefix(120))" }
            md += "\n"
        }
        let e = Distiller.analyze(project: p)
        if !e.conventions.isEmpty {
            md += "\n## 规范\n" + e.conventions.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !e.topCommands.isEmpty {
            md += "\n## 高频命令\n" + e.topCommands.prefix(10).map { "\($0.0) ×\($0.1)" }.joined(separator: "\n") + "\n"
        }
        return md
    }

    static func parseInsight(_ raw: String, project: ProjectAggregate, model: String) throws -> ProjectInsight {
        // Strip markdown fences / prose around the JSON object.
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") {
            s = String(s[start...end])
        }
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.decode("模型未返回合法 JSON")
        }
        let overview = (obj["overview"] as? String) ?? ""
        let highlights = (obj["highlights"] as? [String]) ?? []
        let timeline: [InsightMilestone] = ((obj["timeline"] as? [[String: Any]]) ?? []).map {
            InsightMilestone(
                date: ($0["date"] as? String) ?? "",
                title: ($0["title"] as? String) ?? "",
                detail: ($0["detail"] as? String) ?? "")
        }
        guard !overview.isEmpty || !timeline.isEmpty else { throw AIError.decode("JSON 内容为空") }
        return ProjectInsight(
            projectPath: project.path, generatedAt: Date(), model: model,
            overview: overview, timeline: timeline, highlights: highlights)
    }
}

// MARK: - Skill Distillery

enum Distiller {
    static func analyze(project: ProjectAggregate) -> SkillEvidence {
        var cmdCounts: [String: Int] = [:]
        var tools: [String: Int] = [:]
        var exts: [String: Int] = [:]
        var askCounts: [String: (String, Int)] = [:]

        for s in project.sessions {
            for (k, v) in s.toolCounts { tools[k, default: 0] += v }
            for cmd in s.bashCommands {
                let key = commandSignature(cmd)
                if !key.isEmpty { cmdCounts[key, default: 0] += 1 }
            }
            for f in s.filesTouched {
                let e = (f as NSString).pathExtension.lowercased()
                if !e.isEmpty { exts[e, default: 0] += 1 }
            }
            for p in s.userPrompts {
                let norm = String(p.lowercased().prefix(40))
                let cur = askCounts[norm]
                askCounts[norm] = (p, (cur?.1 ?? 0) + 1)
            }
        }

        let conventions = detectConventions(cmdCounts)
        return SkillEvidence(
            projectPath: project.path,
            sessionCount: project.sessions.count,
            topCommands: cmdCounts.sorted { $0.value > $1.value }.prefix(14).map { ($0.key, $0.value) },
            topTools: tools.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) },
            fileExtensions: exts.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) },
            conventions: conventions,
            recurringAsks: askCounts.values.filter { $0.1 >= 2 }
                .sorted { $0.1 > $1.1 }.prefix(8).map { String($0.0.prefix(120)) })
    }

    /// "git commit -m ..." → "git commit"; "npm run build" → "npm run build"
    static func commandSignature(_ cmd: String) -> String {
        let tokens = cmd.split(separator: " ").map(String.init)
        guard let first = tokens.first else { return "" }
        let head = (first as NSString).lastPathComponent
        guard head.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else { return "" }
        var sig = [head]
        for t in tokens.dropFirst().prefix(2) {
            if t.hasPrefix("-") || t.contains("/") || t.contains("=") || t.count > 20 { break }
            sig.append(t)
            if sig.count == 3 { break }
        }
        return sig.joined(separator: " ")
    }

    static func detectConventions(_ cmds: [String: Int]) -> [String] {
        var out: [String] = []
        func has(_ prefix: String) -> Bool { cmds.keys.contains { $0.hasPrefix(prefix) } }
        if has("pnpm") { out.append("包管理偏好 pnpm") }
        else if has("yarn") { out.append("包管理偏好 yarn") }
        else if has("npm") { out.append("包管理使用 npm") }
        if has("uv ") || has("uv") { out.append("Python 环境用 uv 管理") }
        else if has("poetry") { out.append("Python 环境用 poetry 管理") }
        else if has("pip") { out.append("Python 依赖用 pip 安装") }
        if has("pytest") { out.append("测试跑 pytest") }
        if has("jest") || has("vitest") { out.append("前端测试用 jest/vitest") }
        if has("cargo") { out.append("Rust 工具链 cargo") }
        if has("swift build") || has("xcodebuild") { out.append("Swift/Xcode 构建流") }
        if has("docker") { out.append("使用 Docker 容器化") }
        if has("kubectl") { out.append("涉及 Kubernetes 运维") }
        if has("git push") || has("gh pr") { out.append("有 git 推送/PR 工作流") }
        if has("ssh") || has("scp") || has("rsync") { out.append("涉及远程服务器操作") }
        if has("make") { out.append("使用 Makefile 驱动构建") }
        return out
    }

    static func evidenceMarkdown(_ e: SkillEvidence, projectName: String) -> String {
        var md = "# 证据包：\(projectName)\n\n共 \(e.sessionCount) 个会话。\n\n## 高频命令\n"
        for (c, n) in e.topCommands { md += "- `\(c)` ×\(n)\n" }
        md += "\n## 工具使用\n"
        for (t, n) in e.topTools { md += "- \(t) ×\(n)\n" }
        if !e.fileExtensions.isEmpty {
            md += "\n## 涉及文件类型\n" + e.fileExtensions.map { "`.\($0.0)`×\($0.1)" }.joined(separator: " · ") + "\n"
        }
        if !e.conventions.isEmpty {
            md += "\n## 侦测到的规范\n" + e.conventions.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !e.recurringAsks.isEmpty {
            md += "\n## 反复出现的诉求\n" + e.recurringAsks.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        return md
    }

    static func heuristicSkill(_ e: SkillEvidence, projectName: String) -> DistilledSkill {
        let slug = slugify(projectName)
        var body = """
        ---
        name: \(slug)-playbook
        description: 从 \(projectName) 的 \(e.sessionCount) 个 Agent 会话中蒸馏出的开发规范、常用脚本与工作范式。适用于该项目的后续推进与改造。
        ---

        # \(projectName) 开发手册（蒸馏版）

        """
        if !e.conventions.isEmpty {
            body += "## 开发规范\n" + e.conventions.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !e.topCommands.isEmpty {
            body += "## 高频命令（按使用次数）\n```\n" +
                e.topCommands.map { "\($0.0)    # ×\($0.1)" }.joined(separator: "\n") + "\n```\n\n"
        }
        if !e.recurringAsks.isEmpty {
            body += "## 常见任务模式\n" + e.recurringAsks.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !e.fileExtensions.isEmpty {
            body += "## 主要涉及\n" + e.fileExtensions.map { "`.\($0.0)`" }.joined(separator: " ") + " 类型文件\n"
        }
        return DistilledSkill(
            name: "\(slug)-playbook",
            description: "从 \(projectName) 会话蒸馏的开发范式",
            body: body, origin: "heuristic")
    }

    static func aiPrompt(_ e: SkillEvidence, projectName: String) -> String {
        """
        你是一个「Agent 技能蒸馏器」。下面是从项目 \(projectName) 的 \(e.sessionCount) 个 AI 编程会话中提取的行为证据。\
        请蒸馏出一份可复用的 SKILL.md（YAML frontmatter 含 name 与 description，name 用 kebab-case），\
        内容包括：该项目的开发规范、常用脚本/命令及用途推断、倾向的工作范式、未来推进或改造该项目时应遵循的模式。\
        用中文，直接输出 SKILL.md 全文，不要额外解释。

        \(evidenceMarkdown(e, projectName: projectName))
        """
    }

    static func slugify(_ s: String) -> String {
        let ascii = s.lowercased().map { c -> Character in
            (c.isLetter && c.isASCII) || c.isNumber ? c : "-"
        }
        let collapsed = String(ascii).replacingOccurrences(
            of: "-+", with: "-", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "distilled-skill" : String(trimmed.prefix(40))
    }

    /// Write the skill to its target. Returns the written path.
    enum InjectError: LocalizedError {
        case needsProject
        var errorDescription: String? { "该目标需要先选择一个项目" }
    }

    static func inject(_ skill: DistilledSkill, target: InjectionTarget, projectPath: String?) throws -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        if target.needsProject && projectPath == nil { throw InjectError.needsProject }
        let projectRoot = projectPath.map { URL(fileURLWithPath: $0) }

        if target.isSkillDir {
            let base = target == .claudeSkills
                ? home.appendingPathComponent(".claude/skills")
                : (projectRoot ?? home).appendingPathComponent(".claude/skills")
            let dir = base.appendingPathComponent(skill.name)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("SKILL.md")
            try backupIfExists(file)
            try skill.body.write(to: file, atomically: true, encoding: .utf8)
            return file.path
        }

        // Markdown-append targets — idempotent via a per-skill marker block.
        let file: URL
        switch target {
        case .codexAgentsMd: file = home.appendingPathComponent(".codex/AGENTS.md")
        case .geminiMd: file = home.appendingPathComponent(".gemini/GEMINI.md")
        case .projectAgentsMd: file = (projectRoot ?? home).appendingPathComponent("AGENTS.md")
        case .projectCursorRules: file = (projectRoot ?? home).appendingPathComponent(".cursorrules")
        case .projectWindsurfRules: file = (projectRoot ?? home).appendingPathComponent(".windsurfrules")
        default: file = home.appendingPathComponent(".codex/AGENTS.md")
        }
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try backupIfExists(file)
        let marker = "<!-- vitrine:skill:\(skill.name) -->"
        if let range = existing.range(of: marker) {
            // Replace the previously-injected block (from marker to EOF or next marker).
            existing = String(existing[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let stamp = Date().formatted(.iso8601)
        existing += "\n\n\(marker)\n<!-- 由 Vitrine 蒸馏注入 · \(stamp) -->\n\n\(skill.body)\n"
        try existing.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    static func backupIfExists(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let bak = url.appendingPathExtension("bak-\(stamp)")
        try fm.copyItem(at: url, to: bak)
    }
}

// MARK: - Memory Studio

enum MemoryManager {
    /// Global + Claude-project memory sources. These all live under the home directory
    /// (~/.claude, ~/.codex, ~/.gemini) and never touch ~/Documents, so no TCC prompt.
    static func discoverGlobalSources() -> [MemorySource] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var out: [MemorySource] = []

        func add(_ path: URL, _ kind: MemorySourceKind, project: String? = nil) {
            guard let attrs = try? fm.attributesOfItem(atPath: path.path),
                  let size = attrs[.size] as? Int, size > 0 else { return }
            let mtime = (attrs[.modificationDate] as? Date) ?? .distantPast
            out.append(MemorySource(kind: kind, path: path.path, projectPath: project,
                                    sizeBytes: size, modifiedAt: mtime))
        }

        add(home.appendingPathComponent(".claude/CLAUDE.md"), .claudeGlobal)
        add(home.appendingPathComponent(".codex/AGENTS.md"), .codexGlobal)
        add(home.appendingPathComponent(".gemini/GEMINI.md"), .geminiGlobal)

        let projRoot = home.appendingPathComponent(".claude/projects")
        if let dirs = try? fm.contentsOfDirectory(at: projRoot, includingPropertiesForKeys: nil) {
            for d in dirs {
                let mem = d.appendingPathComponent("memory/MEMORY.md")
                if fm.fileExists(atPath: mem.path) {
                    add(mem, .claudeProjectMemory,
                        project: ClaudeScanner.decodeProjectDir(d.lastPathComponent))
                }
            }
        }
        return out.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// In-repo instruction files (CLAUDE.md/AGENTS.md/.cursorrules/copilot) for known projects.
    /// These live under ~/Documents etc., so the first call triggers a one-time macOS
    /// file-access prompt — hence it is user-initiated, not run at launch.
    static func discoverProjectSources(projects: [ProjectAggregate]) -> [MemorySource] {
        let fm = FileManager.default
        var out: [MemorySource] = []
        func add(_ path: URL, _ kind: MemorySourceKind, project: String) {
            guard let attrs = try? fm.attributesOfItem(atPath: path.path),
                  let size = attrs[.size] as? Int, size > 0 else { return }
            let mtime = (attrs[.modificationDate] as? Date) ?? .distantPast
            out.append(MemorySource(kind: kind, path: path.path, projectPath: project,
                                    sizeBytes: size, modifiedAt: mtime))
        }
        for p in projects {
            let root = URL(fileURLWithPath: p.path)
            guard fm.fileExists(atPath: root.path) else { continue }
            add(root.appendingPathComponent("CLAUDE.md"), .projectClaudeMd, project: p.path)
            add(root.appendingPathComponent("AGENTS.md"), .projectAgentsMd, project: p.path)
            add(root.appendingPathComponent(".cursorrules"), .cursorRules, project: p.path)
            add(root.appendingPathComponent(".windsurfrules"), .windsurfRules, project: p.path)
            add(root.appendingPathComponent(".github/copilot-instructions.md"), .copilotInstructions, project: p.path)
        }
        return out.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Parse a source into items: memory-file frontmatter entries, or "## " sections.
    static func parse(_ source: MemorySource) -> [MemoryItem] {
        guard let text = try? String(contentsOfFile: source.path, encoding: .utf8) else { return [] }

        if source.kind == .claudeProjectMemory {
            // MEMORY.md is an index; parse sibling memory files with frontmatter.
            let dir = (source.path as NSString).deletingLastPathComponent
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            var items: [MemoryItem] = []
            for f in files where f.hasSuffix(".md") && f != "MEMORY.md" {
                let path = dir + "/" + f
                guard let body = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                items.append(parseMemoryFile(body, path: path, source: source)
                             ?? MemoryItem(id: path, sourcePath: source.path, sourceKind: source.kind,
                                           name: f, type: "section", body: String(body.prefix(2000))))
            }
            if items.isEmpty {
                items = sections(of: text, source: source)
            }
            return items
        }
        return sections(of: text, source: source)
    }

    private static func parseMemoryFile(_ text: String, path: String, source: MemorySource) -> MemoryItem? {
        guard text.hasPrefix("---") else { return nil }
        let parts = text.components(separatedBy: "---")
        guard parts.count >= 3 else { return nil }
        let front = parts[1]
        let body = parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
        func field(_ key: String) -> String? {
            for line in front.split(separator: "\n") {
                let l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("\(key):") {
                    return String(l.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }
        return MemoryItem(
            id: path, sourcePath: source.path, sourceKind: source.kind,
            name: field("name") ?? (path as NSString).lastPathComponent,
            type: field("type") ?? "project",
            body: String(body.prefix(2000)))
    }

    private static func sections(of text: String, source: MemorySource) -> [MemoryItem] {
        var items: [MemoryItem] = []
        var currentTitle = "（导言）"
        var currentBody: [String] = []
        func flush() {
            let body = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                items.append(MemoryItem(
                    id: source.path + "#" + currentTitle + "#\(items.count)",
                    sourcePath: source.path, sourceKind: source.kind,
                    name: currentTitle, type: "section", body: String(body.prefix(2000))))
            }
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") || line.hasPrefix("# ") {
                flush()
                currentTitle = line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).trimmingCharacters(in: .whitespaces)
                currentBody = []
            } else {
                currentBody.append(line)
            }
        }
        flush()
        return items
    }

    /// Merge selected items into a single markdown doc for the target agent's dialect.
    static func merged(_ items: [MemoryItem], targetName: String) -> String {
        var md = "<!-- 由 Vitrine 记忆工坊合并生成 · \(Date().formatted(.iso8601)) -->\n"
        md += "# 迁移记忆（供 \(targetName)）\n"
        let grouped = Dictionary(grouping: items, by: \.type)
        let order = ["project", "feedback", "user", "reference", "section"]
        let typeNames = ["project": "项目背景", "feedback": "工作方式反馈", "user": "用户画像",
                         "reference": "外部参考", "section": "规范片段"]
        for t in order {
            guard let group = grouped[t], !group.isEmpty else { continue }
            md += "\n## \(typeNames[t] ?? t)\n"
            for item in group {
                md += "\n### \(item.name)\n"
                md += "<!-- 来源: \(item.sourcePath) -->\n"
                md += item.body + "\n"
            }
        }
        return md
    }

    /// Write merged memory, backing up any existing file. Returns written path.
    static func write(_ text: String, to path: String, append: Bool) throws -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Distiller.backupIfExists(url)
        if append, let existing = try? String(contentsOf: url, encoding: .utf8) {
            try (existing + "\n\n" + text).write(to: url, atomically: true, encoding: .utf8)
        } else {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return url.path
    }
}
