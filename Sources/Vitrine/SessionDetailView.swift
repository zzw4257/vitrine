import SwiftUI

// MARK: - Transcript loading (on demand, capped)

struct TranscriptEntry: Identifiable {
    enum Kind { case user, assistant, tool }
    var id: Int
    var kind: Kind
    var text: String
}

enum TranscriptLoader {
    static func load(_ session: SessionRecord, cap: Int = 400) -> [TranscriptEntry] {
        var out: [TranscriptEntry] = []
        var n = 0
        func add(_ kind: TranscriptEntry.Kind, _ text: String) {
            guard out.count < cap else { return }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            out.append(TranscriptEntry(id: n, kind: kind, text: String(t.prefix(1200))))
            n += 1
        }
        let url = URL(fileURLWithPath: session.filePath)
        switch session.agent {
        case .claude:
            JSONL.forEachLine(of: url) { obj in
                guard out.count < cap,
                      let type = obj["type"] as? String,
                      let msg = obj["message"] as? [String: Any] else { return }
                if (obj["isSidechain"] as? Bool) == true { return }
                if type == "user" {
                    if let s = msg["content"] as? String, let c = JSONL.cleanPrompt(s) { add(.user, c) }
                    else if let blocks = msg["content"] as? [[String: Any]] {
                        for b in blocks where (b["type"] as? String) == "text" {
                            if let c = (b["text"] as? String).flatMap(JSONL.cleanPrompt) { add(.user, c) }
                        }
                    }
                } else if type == "assistant", let blocks = msg["content"] as? [[String: Any]] {
                    for b in blocks {
                        switch b["type"] as? String {
                        case "text":
                            if let t = b["text"] as? String { add(.assistant, t) }
                        case "tool_use":
                            let name = (b["name"] as? String) ?? "tool"
                            let input = b["input"] as? [String: Any]
                            let hint = (input?["command"] as? String)
                                ?? (input?["file_path"] as? String)
                                ?? (input?["description"] as? String) ?? ""
                            add(.tool, "\(name)  \(String(hint.prefix(120)))")
                        default: break
                        }
                    }
                }
            }
        case .codex:
            JSONL.forEachLine(of: url) { obj in
                guard out.count < cap,
                      (obj["type"] as? String) == "response_item",
                      let payload = obj["payload"] as? [String: Any] else { return }
                switch payload["type"] as? String {
                case "message":
                    let role = payload["role"] as? String
                    for c in (payload["content"] as? [[String: Any]]) ?? [] {
                        let ct = c["type"] as? String
                        if role == "user", ct == "input_text",
                           let t = (c["text"] as? String).flatMap(JSONL.cleanPrompt) {
                            add(.user, t)
                        } else if role == "assistant", ct == "output_text", let t = c["text"] as? String {
                            add(.assistant, t)
                        }
                    }
                case "function_call":
                    add(.tool, ((payload["name"] as? String) ?? "tool"))
                case "local_shell_call":
                    let cmd = ((payload["action"] as? [String: Any])?["command"] as? [String])?
                        .joined(separator: " ") ?? ""
                    add(.tool, "shell  \(String(cmd.prefix(120)))")
                default: break
                }
            }
        default:
            break
        }
        return out
    }
}

// MARK: - Detail sheet

struct SessionDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss
    var session: SessionRecord

    @State private var transcript: [TranscriptEntry] = []
    @State private var loading = true
    @State private var summarizing = false
    @State private var summaryError: String?

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(alignment: .leading, spacing: 14) {
                header
                summaryCard
                transcriptList
            }
            .padding(20)
        }
        .frame(minWidth: 560, idealWidth: 860, maxWidth: 1100,
               minHeight: 480, idealHeight: 640, maxHeight: 900)
        .escapeToDismiss(dismiss)
        .task {
            let t = await Task.detached(priority: .userInitiated) {
                TranscriptLoader.load(session)
            }.value
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                transcript = t
                loading = false
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AgentBadge(agent: session.agent)
                if session.isSubagent { GlassChip(text: "子代理", color: .gray) }
                Spacer()
                Button {
                    NSWorkspace.shared.selectFile(session.filePath, inFileViewerRootedAtPath: "")
                } label: {
                    Label("原始文件", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.vitrine)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.vitrine)
            }
            Text(store.displayTitle(session))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(2)
            if store.displayTitle(session) != session.title {
                Text("原始标题：\(session.title)")
                    .font(.system(size: 10.5)).foregroundStyle(theme.textFaint).lineLimit(1)
            }
            HStack(spacing: 8) {
                GlassChip(text: session.projectName, color: V.violet, systemImage: "folder")
                GlassChip(text: Fmt.day(session.startedAt) + " · " + Fmt.duration(session.duration),
                          color: V.sky, systemImage: "clock")
                GlassChip(text: "\(session.userMessages)问 / \(session.assistantMessages)答",
                          color: V.teal, systemImage: "bubble.left.and.bubble.right")
                if session.totalTokens > 0 {
                    GlassChip(text: Fmt.tokens(session.totalTokens) + (session.tokensEstimated ? "~" : "") + " tok",
                              color: V.amber, systemImage: "bolt")
                }
                if let b = session.gitBranch {
                    GlassChip(text: b, color: V.rose, systemImage: "arrow.triangle.branch")
                }
                ForEach(session.models.prefix(2), id: \.self) { m in
                    let label = ModelInfo.label(m)
                    if !label.isEmpty { GlassChip(text: label, color: ModelInfo.vendorColor(label)) }
                }
            }
        }
    }

    private var hasAISummary: Bool { store.summaries[session.id] != nil }

    private var summaryCard: some View {
        // Distinct treatment: an AI summary is accent-tinted and badged; before that,
        // the card is muted and explicitly labelled a machine excerpt (节选), not a summary.
        GlassCard(tint: hasAISummary ? V.teal : nil, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if hasAISummary {
                        Label("AI 总结", systemImage: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(V.teal)
                        GlassChip(text: "AI 生成", color: V.teal)
                    } else {
                        Label("会话节选", systemImage: "doc.text")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(V.textDim)
                        GlassChip(text: "机器摘要 · 非 AI", color: .secondary)
                    }
                    Spacer()
                    if store.aiAvailable {
                        Button {
                            summarizing = true
                            summaryError = nil
                            Task {
                                do { try await store.generateAISummary(for: session) }
                                catch { summaryError = error.localizedDescription }
                                summarizing = false
                            }
                        } label: {
                            if summarizing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(hasAISummary ? "重新总结" : "AI 总结",
                                      systemImage: "wand.and.stars")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .buttonStyle(.vitrineProminent)
                        .disabled(summarizing)
                    }
                }
                RichText(text: store.summary(for: session), size: 12.5,
                         textColor: hasAISummary ? theme.textStrong : theme.textDim)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !hasAISummary {
                    Text("以上为从会话元数据机械生成的节选，点击「AI 总结」获得真正的语义总结。")
                        .font(.system(size: 10)).foregroundStyle(V.textDim.opacity(0.8))
                }
                if let e = summaryError {
                    Text("AI 总结失败：\(e)").font(.system(size: 10.5)).foregroundStyle(V.rose)
                }
            }
        }
    }

    private var transcriptList: some View {
        GlassCard(padding: 0) {
            Group {
                if loading {
                    ProgressView("读取转录…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if transcript.isEmpty {
                    if !session.filesTouched.isEmpty || !session.bashCommands.isEmpty {
                        footprintView
                    } else {
                        EmptyHint(symbol: "text.bubble",
                                  text: session.agent == .opencode ? "opencode 转录暂不支持内嵌预览" : "无可显示内容")
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(transcript.enumerated()), id: \.element.id) { i, e in
                                TranscriptBubble(entry: e)
                                    .appearStagger(min(i, 16), trigger: transcript.count, baseDelay: 0.05, perItem: 0.03)
                            }
                        }
                        .padding(14)
                    }
                    .scrollIndicators(.never)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// For sources without a readable transcript (Cursor summary DB, Windsurf's encrypted store),
    /// show the honest activity footprint we could recover instead of a blank "no content".
    private var footprintView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(session.agent == .windsurf
                      ? "Windsurf 的对话在本地加密存储，无法读取逐轮转录；以下是它在本项目触碰过的文件足迹。"
                      : "该来源未提供逐轮转录，以下是可还原的活动足迹。",
                      systemImage: "lock.doc")
                    .font(.system(size: 11.5)).foregroundStyle(V.textDim)
                    .padding(.bottom, 2)

                if !session.filesTouched.isEmpty {
                    SectionHeader(title: "触碰的文件", subtitle: "\(session.filesTouched.count) 个",
                                  icon: "doc.on.doc.fill", iconColor: V.mint)
                    ForEach(Array(session.filesTouched.prefix(200).enumerated()), id: \.element) { i, f in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text").font(.system(size: 10)).foregroundStyle(V.textDim)
                            Text(f).font(.system(size: 11.5, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(theme.well.opacity(0.5), in: .rect(cornerRadius: 7))
                        .hoverLift(1.01)
                        .appearStagger(min(i, 16), trigger: session.id, baseDelay: 0.04, perItem: 0.03)
                    }
                }

                if !session.bashCommands.isEmpty {
                    SectionHeader(title: "命令", subtitle: "\(session.bashCommands.count) 条",
                                  icon: "terminal.fill", iconColor: V.teal)
                    ForEach(Array(session.bashCommands.prefix(60).enumerated()), id: \.offset) { i, c in
                        Syntax.line(c, size: 11).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(theme.well.opacity(0.5), in: .rect(cornerRadius: 7))
                            .hoverLift(1.01)
                            .appearStagger(min(i, 16), trigger: session.id, baseDelay: 0.04, perItem: 0.03)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }
}

private struct TranscriptBubble: View {
    var entry: TranscriptEntry

    var body: some View {
        switch entry.kind {
        case .user:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(V.teal)
                    .padding(.top, 3)
                RichText(text: entry.text, size: 12, textColor: .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(V.teal.opacity(0.09), in: .rect(cornerRadius: 12))
        case .assistant:
            RichText(text: entry.text, size: 12, textColor: .secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
        case .tool:
            HStack(spacing: 6) {
                Image(systemName: "wrench.fill").font(.system(size: 8))
                Text(entry.text).font(.vMono).lineLimit(1)
            }
            .foregroundStyle(V.textDim)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.primary.opacity(0.06), in: .capsule)
        }
    }
}
