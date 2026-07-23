import SwiftUI

struct PinnedView: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @State private var installMessage: (String, Bool)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已置顶").themedDisplay(24)
                    Text("在任意已安装 Agent CLI 里说「置顶这个对话」，它就会出现在这里，带独立标签与一键恢复")
                        .font(.system(size: 12)).foregroundStyle(V.textDim)
                }
                .padding(.top, 26)

                installCard

                if store.pinnedEntries.isEmpty {
                    EmptyHint(symbol: "pin", text: "还没有置顶的对话\n先在下方安装一个 Agent 的 Pin 技能，然后去那个 CLI 里说「置顶这个对话」")
                        .frame(height: 220)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(store.pinnedEntries.enumerated()), id: \.element.filePath) { i, entry in
                            PinnedRow(entry: entry)
                                .appearStagger(i, trigger: store.pins.count, baseDelay: 0.03, perItem: 0.04)
                        }
                    }
                }
            }
            .padding(22)
            .centeredContent()
        }
        .scrollIndicators(.never)
    }

    private var installCard: some View {
        GlassCard(tint: V.violet) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "安装 Pin 技能", subtitle: "给本机已检测到的 Agent CLI 装上「置顶」命令 · 每个都可单独安装/重装",
                              icon: "pin.circle", iconColor: V.violet)
                HStack(spacing: 8) {
                    ForEach(PinInstaller.supported, id: \.agent) { entry in
                        InstallChip(agent: entry.agent, confidence: entry.confidence,
                                    detected: store.cliTools.contains { $0.agent == entry.agent }) {
                            do {
                                let path = try PinInstaller.install(for: entry.agent)
                                withAnimation { installMessage = ("已安装到 \(path)", false) }
                            } catch {
                                withAnimation { installMessage = ("安装失败：\(error.localizedDescription)", true) }
                            }
                        }
                    }
                }
                if let (text, isError) = installMessage {
                    Label(text, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(isError ? V.rose : V.teal)
                        .transition(.opacity)
                }
                Text("Claude Code / Codex 用各自官方文档确认过的机制精确定位当前会话；Gemini CLI / opencode 目前只能"
                   + "尽力而为（取该目录下最新的会话文件），标 ⚠️ 提示。安装只写入技能/命令文件，不会改动你已有的 CLAUDE.md / AGENTS.md。")
                    .font(.system(size: 10)).foregroundStyle(theme.textDim)
            }
        }
    }
}

private struct InstallChip: View {
    var agent: AgentKind
    var confidence: PinInstaller.Confidence
    var detected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: agent.symbol).font(.system(size: 11, weight: .semibold))
                Text(agent.display).font(.system(size: 11.5, weight: .medium))
                if confidence == .bestEffort {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9)).foregroundStyle(V.amber)
                }
                if !detected {
                    Text("未检测到").font(.system(size: 9)).foregroundStyle(V.textDim)
                }
            }
            .foregroundStyle(agent.color)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(agent.color.opacity(0.3), lineWidth: 1))
        .hoverLift(1.03)
        .help(confidence == .bestEffort
              ? "\(agent.display)：会话定位是尽力而为的启发式，未逐一实测"
              : "\(agent.display)：会话定位机制已对照官方文档确认")
    }
}

private struct PinnedRow: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @Environment(\.openSession) private var openSession
    var entry: (filePath: String, pin: PinRecord, session: SessionRecord?)
    @State private var editingLabel = false
    @State private var labelDraft = ""
    @State private var summarizing = false

    private var agent: AgentKind { AgentKind(rawValue: entry.pin.agent) ?? .other }
    private var resumeCommand: String? {
        guard let sid = PinResume.sessionId(agent: agent, filePath: entry.filePath) else { return nil }
        return PinResume.command(agent: agent, sessionId: sid)
    }
    private var cliInstalled: Bool { store.cliTools.contains { $0.agent == agent } }

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    AgentBadge(agent: agent, compact: true)
                    if editingLabel {
                        TextField("标签", text: $labelDraft)
                            .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
                            .onSubmit(commitLabel)
                        Button("保存") { commitLabel() }.buttonStyle(.vitrine)
                    } else {
                        Text(entry.pin.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Button { labelDraft = entry.pin.label; editingLabel = true } label: {
                            Image(systemName: "pencil").font(.system(size: 9))
                        }.buttonStyle(.plain).foregroundStyle(V.textDim)
                    }
                    Spacer()
                    Text(Fmt.relative(JSONL.date(entry.pin.pinnedAt) ?? .distantPast))
                        .font(.system(size: 10)).foregroundStyle(V.textDim)
                    Button { store.unpin(entry.filePath) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                    }.buttonStyle(.plain).foregroundStyle(V.textDim)
                        .help("取消置顶")
                }

                if let s = entry.session {
                    HStack(spacing: 6) {
                        GlassChip(text: s.projectName, color: V.violet, systemImage: "folder")
                        Text(Fmt.day(s.startedAt) + " · " + Fmt.relative(s.startedAt))
                            .font(.system(size: 10)).foregroundStyle(V.textDim)
                    }
                    Text(store.pinSummaries[entry.filePath] ?? store.summary(for: s))
                        .font(.system(size: 11.5)).foregroundStyle(theme.textDim).lineLimit(2)
                } else {
                    Label("尚未匹配到本地会话（可能还未扫描，或转录已被移动/删除）", systemImage: "questionmark.folder")
                        .font(.system(size: 11)).foregroundStyle(V.textDim)
                }

                HStack(spacing: 8) {
                    if let s = entry.session {
                        Button { openSession(s) } label: {
                            Label("查看", systemImage: "doc.text.magnifyingglass").font(.system(size: 11, weight: .semibold))
                        }.buttonStyle(.vitrine)
                        if store.aiAvailable {
                            Button {
                                summarizing = true
                                Task { try? await store.generatePinSummary(for: s); summarizing = false }
                            } label: {
                                if summarizing { ProgressView().controlSize(.small) }
                                else { Label("智能总结", systemImage: "sparkles").font(.system(size: 11, weight: .semibold)) }
                            }
                            .buttonStyle(.vitrine)
                            .disabled(summarizing)
                        }
                    }
                    if let cmd = resumeCommand, let s = entry.session {
                        Button {
                            CLI.launchInTerminal(command: cmd, cwd: s.projectPath)
                        } label: {
                            Label("恢复", systemImage: "arrow.uturn.forward.circle.fill").font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.vitrineProminent)
                        .disabled(!cliInstalled)
                        .help(cliInstalled ? cmd : "未检测到 \(agent.display) CLI")
                    }
                    Spacer()
                }
            }
        }
    }

    private func commitLabel() {
        let trimmed = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        store.renamePin(entry.filePath, label: trimmed.isEmpty ? entry.pin.label : trimmed)
        editingLabel = false
    }
}
