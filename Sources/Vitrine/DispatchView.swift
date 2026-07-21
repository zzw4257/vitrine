import SwiftUI

struct DispatchView: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @State private var projectPath: String?
    @State private var toolName: String = "claude"
    @State private var prompt = ""
    @State private var injectBriefing = true
    @State private var launched: String?
    @State private var runningAgents: [String] = []
    @State private var refreshTick = 0

    private var project: ProjectAggregate? { store.projects.first { $0.path == projectPath } }
    private var tool: CLITool? { store.cliTools.first { $0.name == toolName } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("任务调配").themedDisplay(24)
                    Text("统一面板：选项目、选 Agent、注入项目记忆简报，一键在终端拉起")
                        .font(.system(size: 12)).foregroundStyle(V.textDim)
                }
                .padding(.top, 26)

                HStack(alignment: .top, spacing: 14) {
                    // Config column
                    VStack(spacing: 14) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "目标项目")
                                Picker("", selection: $projectPath) {
                                    Text("选择项目…").tag(String?.none)
                                    ForEach(store.projects) { p in
                                        Text(p.name).tag(String?.some(p.path))
                                    }
                                }
                                .labelsHidden()
                                if let p = project {
                                    HStack(spacing: 6) {
                                        ForEach(p.agents) { AgentBadge(agent: $0, compact: true) }
                                        Text("已有 \(p.sessions.count) 会话 · 最近 \(Fmt.relative(p.lastActivity))")
                                            .font(.system(size: 10.5)).foregroundStyle(V.textDim)
                                    }
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "执行 Agent", subtitle: "已在本机检测到的 CLI")
                                HStack(spacing: 8) {
                                    ForEach(store.cliTools) { t in
                                        AgentPickButton(tool: t, selected: toolName == t.name) {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                toolName = t.name
                                            }
                                        }
                                    }
                                }
                                if let t = tool {
                                    Text(t.path).font(.vMono).foregroundStyle(V.textDim).lineLimit(1)
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "任务描述")
                                TextEditor(text: $prompt)
                                    .font(.system(size: 12.5))
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(height: 120)
                                    .background(theme.well, in: .rect(cornerRadius: 12))
                                Toggle("注入项目记忆简报（生成 .vitrine-briefing.md，含项目脉络 + 历史会话摘要）",
                                       isOn: $injectBriefing)
                                    .toggleStyle(.switch).controlSize(.mini)
                                    .font(.system(size: 11)).foregroundStyle(V.textDim)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .appearStagger(0, trigger: projectPath ?? "")

                    // Launch column
                    VStack(spacing: 14) {
                        GlassCard(tint: V.teal) {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "启动命令", icon: "terminal.fill", iconColor: V.teal)
                                Group {
                                    if command.isEmpty {
                                        Text("…").font(.vMono).foregroundStyle(theme.textFaint)
                                    } else {
                                        Syntax.line(command, size: 12).textSelection(.enabled)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(theme.well, in: .rect(cornerRadius: 10))
                                HStack {
                                    Button {
                                        CLI.copyToPasteboard("cd \(CLI.shellQuote(projectPath ?? ".")) && \(command)")
                                    } label: {
                                        Label("复制", systemImage: "doc.on.doc")
                                            .font(.system(size: 11.5, weight: .semibold))
                                    }
                                    .buttonStyle(.vitrine)
                                    .disabled(command.isEmpty)

                                    Button {
                                        launch()
                                    } label: {
                                        Label("在终端启动", systemImage: "paperplane.fill")
                                            .font(.system(size: 11.5, weight: .semibold))
                                    }
                                    .buttonStyle(.vitrineProminent)
                                    .disabled(command.isEmpty || project == nil)
                                }
                                if let l = launched {
                                    Label(l, systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 10.5)).foregroundStyle(V.teal)
                                        .lineLimit(2)
                                        .transition(.opacity)
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    SectionHeader(title: "正在运行的 Agent 进程")
                                    Spacer()
                                    Button {
                                        refreshTick += 1
                                        refreshRunning()
                                    } label: {
                                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                                            .symbolEffect(.rotate, value: refreshTick)
                                    }
                                    .buttonStyle(.vitrine)
                                }
                                if runningAgents.isEmpty {
                                    VStack(spacing: 6) {
                                        Image(systemName: "moon.zzz")
                                            .font(.system(size: 20)).foregroundStyle(theme.textFaint)
                                        Text("当前没有运行中的 agent CLI")
                                            .font(.system(size: 11)).foregroundStyle(V.textDim)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                } else {
                                    ForEach(Array(runningAgents.enumerated()), id: \.element) { i, line in
                                        Text(line).font(.vMono).lineLimit(1).foregroundStyle(.secondary)
                                            .appearStagger(i, trigger: runningAgents.count, baseDelay: 0.02, perItem: 0.04)
                                    }
                                }
                            }
                        }
                    }
                    .frame(minWidth: 320, idealWidth: 400, maxWidth: 440)
                    .appearStagger(1, trigger: projectPath ?? "")
                }
            }
            .padding(22)
            .centeredContent(1240)
        }
        .scrollIndicators(.never)
        .onAppear {
            selectDefaults()
            refreshRunning()
        }
        .onChange(of: store.projects.count) { selectDefaults() }
        .onChange(of: store.cliTools.count) { selectDefaults() }
    }

    private func selectDefaults() {
        if projectPath == nil {
            let hint = ProcessInfo.processInfo.environment["VITRINE_DISPATCH_PROJECT"]
            if let hint, let m = store.projects.first(where: { $0.name.contains(hint) || $0.path.contains(hint) }) {
                projectPath = m.path
            } else {
                projectPath = store.projects.first?.path
            }
        }
        if !store.cliTools.contains(where: { $0.name == toolName }), let first = store.cliTools.first {
            toolName = first.name
        }
        if prompt.isEmpty, let seed = ProcessInfo.processInfo.environment["VITRINE_DISPATCH_PROMPT"] {
            prompt = seed
        }
    }

    // MARK: Command building

    private var effectivePrompt: String {
        let base = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard injectBriefing else { return base }
        let lead = "请先阅读 .vitrine-briefing.md 了解项目脉络与历史工作，然后执行："
        return base.isEmpty ? lead + "（见简报中的待办）" : lead + base
    }

    private var command: String {
        guard tool != nil else { return "" }
        let q = CLI.shellQuote(effectivePrompt)
        switch toolName {
        case "claude": return "claude \(q)"
        case "codex": return "codex \(q)"
        case "opencode": return "opencode run \(q)"
        case "gemini": return "gemini -i \(q)"
        case "cursor-agent": return "cursor-agent \(q)"
        case "windsurf": return "windsurf ."   // IDE: open the project (briefing file sits in cwd)
        default: return toolName
        }
    }

    private func launch() {
        guard let p = project else { return }
        if injectBriefing {
            let briefing = Self.briefing(for: p, store: store)
            try? briefing.write(
                toFile: p.path + "/.vitrine-briefing.md", atomically: true, encoding: .utf8)
        }
        var cmd = command
        if let t = tool {
            // Use the absolute path so Terminal doesn't depend on PATH.
            cmd = cmd.replacingOccurrences(of: toolName, with: CLI.shellQuote(t.path), options: .anchored)
        }
        CLI.launchInTerminal(command: cmd, cwd: p.path)
        withAnimation { launched = "已在 Terminal 拉起 \(toolName) · \(Date().formatted(date: .omitted, time: .standard))" }
    }

    /// Project briefing: the "memory transfer" payload handed to whichever agent takes over.
    static func briefing(for p: ProjectAggregate, store: AppStore) -> String {
        var md = """
        <!-- 由 Vitrine 任务调配台生成 · \(Date().formatted(.iso8601)) -->
        # 项目简报：\(p.name)

        - 路径：\(p.path)
        - 历史：\(p.sessions.count) 个 Agent 会话，跨 \(p.spanDays) 天（实际活跃 \(p.activeDays) 天）
        - 参与过的 Agent：\(p.agents.map(\.display).joined(separator: "、"))

        ## 最近的工作（新→旧）
        """
        for s in p.sessions.sorted(by: { $0.startedAt > $1.startedAt }).prefix(10) {
            md += "\n- [\(s.agent.display)] \(Fmt.day(s.startedAt))：\(s.title)"
            if let sum = store.summaries[s.id] {
                md += "\n  - \(sum.replacingOccurrences(of: "\n", with: " "))"
            }
        }
        let evidence = Distiller.analyze(project: p)
        if !evidence.conventions.isEmpty {
            md += "\n\n## 本项目的已知规范\n" + evidence.conventions.map { "- \($0)" }.joined(separator: "\n")
        }
        if !evidence.topCommands.isEmpty {
            md += "\n\n## 高频命令\n```\n" + evidence.topCommands.prefix(8)
                .map { "\($0.0)" }.joined(separator: "\n") + "\n```"
        }
        return md
    }

    private func refreshRunning() {
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/ps")
            p.arguments = ["-Ao", "pid,etime,command"]
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let lines = (String(data: data, encoding: .utf8) ?? "")
                .split(separator: "\n").map(String.init)
                .filter { line in
                    ["claude", "codex", "opencode", "gemini", "cursor-agent", "windsurf", "paseo"].contains { name in
                        line.contains("/\(name)") || line.hasSuffix(" \(name)")
                    }
                }
                .filter { !$0.contains("Vitrine") && !$0.contains("grep") }
                .prefix(6)
                .map { String($0.prefix(90)) }
            DispatchQueue.main.async {
                withAnimation { runningAgents = Array(lines) }
            }
        }
    }
}

private struct AgentPickButton: View {
    @Environment(ThemeManager.self) private var theme
    var tool: CLITool
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: tool.agent.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolEffect(.bounce, value: selected)
                Text(tool.name).font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(selected ? tool.agent.color : theme.textDim)
            .frame(width: 66, height: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if selected {
                theme.selectionFill(RoundedRectangle(cornerRadius: 12, style: .continuous), tint: tool.agent.color)
            } else {
                RoundedRectangle(cornerRadius: 12).strokeBorder(theme.hairline, lineWidth: 1)
            }
        }
        .hoverLift(1.03)
    }
}
