import SwiftUI

struct MemoryStudioView: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @State private var selectedSource: MemorySource?
    @State private var items: [MemoryItem] = []
    @State private var picked: [MemoryItem] = []
    @State private var targetPath = "~/.claude/CLAUDE.md"
    @State private var targetName = "Claude Code"
    @State private var appendMode = true
    @State private var writeResult: String?
    @State private var writeError: String?

    var body: some View {
        GeometryReader { geo in
            // Three flexible panes; when the window is too narrow to hold all three
            // comfortably the middle "items" pane yields first (it's the least essential
            // once you've picked sources), keeping picking + merging usable.
            let narrow = geo.size.width < 720
            HStack(spacing: 0) {
                sourceColumn.frame(minWidth: 200, maxWidth: narrow ? .infinity : 300)
                Divider().opacity(0.15)
                if !narrow {
                    itemColumn.frame(maxWidth: .infinity)
                    Divider().opacity(0.15)
                }
                mergeColumn.frame(minWidth: 260, maxWidth: narrow ? .infinity : 380)
            }
            .frame(maxWidth: 1500).frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: Sources

    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("记忆工坊").themedDisplay(24)
                Text("提取 · 合并 · 跨 Agent 迁移").font(.system(size: 12)).foregroundStyle(V.textDim)
            }
            .padding(.top, 26)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(store.memorySources.enumerated()), id: \.element.id) { i, src in
                        SourceRow(source: src, selected: selectedSource?.id == src.id) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                selectedSource = src
                                items = MemoryManager.parse(src)
                            }
                        }
                        .appearStagger(i, trigger: store.memorySources.count)
                    }
                    if store.memorySources.isEmpty {
                        EmptyHint(symbol: "brain", text: "未发现记忆文件").frame(height: 200)
                    }
                    if !store.projectSourcesLoaded {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                store.loadProjectMemorySources()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.plus").font(.system(size: 12, weight: .semibold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("扫描项目内规则文件").font(.system(size: 12, weight: .semibold))
                                    Text("CLAUDE.md · AGENTS.md · .cursorrules（首次需授权 Documents）")
                                        .font(.system(size: 9.5)).foregroundStyle(V.textDim)
                                }
                                Spacer()
                            }
                            .foregroundStyle(V.teal)
                            .padding(.horizontal, 11).padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(V.teal.opacity(0.14)), in: .rect(cornerRadius: 12))
                        .padding(.top, 6)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Items of selected source

    private var itemColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: selectedSource.map { ($0.path as NSString).lastPathComponent } ?? "记忆条目",
                              subtitle: selectedSource != nil ? "\(items.count) 条 · 点击加入合并区" : "先在左侧选择来源")
                Spacer()
                if !items.isEmpty {
                    Button("全部加入") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            for i in items where !picked.contains(where: { $0.id == i.id }) {
                                picked.append(i)
                            }
                        }
                    }
                    .buttonStyle(.vitrine)
                    .font(.system(size: 11))
                }
            }
            .padding(.top, 30)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        MemoryItemCard(item: item, added: picked.contains { $0.id == item.id }) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                if let idx = picked.firstIndex(where: { $0.id == item.id }) {
                                    picked.remove(at: idx)
                                } else {
                                    picked.append(item)
                                }
                            }
                        }
                        .appearStagger(min(i, 20), trigger: selectedSource?.id ?? "", baseDelay: 0.03, perItem: 0.03)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Merge / transfer

    private var mergeColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "合并区", subtitle: "\(picked.count) 条已选")
                Spacer()
                if !picked.isEmpty {
                    Button("清空") {
                        withAnimation { picked.removeAll() }
                    }
                    .buttonStyle(.vitrine).font(.system(size: 11))
                }
            }
            .padding(.top, 30)

            if picked.isEmpty {
                EmptyHint(symbol: "tray.and.arrow.down", text: "从中间加入记忆条目\n合并后可迁移到任何 Agent")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(picked) { item in
                            HStack(spacing: 8) {
                                GlassChip(text: item.type, color: typeColor(item.type))
                                Text(item.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                                Spacer()
                                Button {
                                    withAnimation { picked.removeAll { $0.id == item.id } }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(V.textDim)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .glassEffect(.regular, in: .rect(cornerRadius: 10))
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 240)

                GlassCard(tint: V.teal, padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("迁移目标", systemImage: "arrow.uturn.right")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(V.teal)
                        Picker("", selection: $targetPath) {
                            Label("Claude 全局 · CLAUDE.md", systemImage: AgentKind.claude.symbol).tag("~/.claude/CLAUDE.md")
                            Label("Codex 全局 · AGENTS.md", systemImage: AgentKind.codex.symbol).tag("~/.codex/AGENTS.md")
                            Label("Gemini 全局 · GEMINI.md", systemImage: AgentKind.gemini.symbol).tag("~/.gemini/GEMINI.md")
                            ForEach(store.projects.prefix(12)) { p in
                                Text("\(p.name) · CLAUDE.md").tag(p.path + "/CLAUDE.md")
                                Text("\(p.name) · AGENTS.md").tag(p.path + "/AGENTS.md")
                                Text("\(p.name) · .cursorrules").tag(p.path + "/.cursorrules")
                                Text("\(p.name) · .windsurfrules").tag(p.path + "/.windsurfrules")
                            }
                        }
                        .labelsHidden()
                        Toggle("追加模式（保留原文件内容）", isOn: $appendMode)
                            .toggleStyle(.switch).controlSize(.mini)
                            .font(.system(size: 11)).foregroundStyle(V.textDim)

                        HStack {
                            Button {
                                CLI.copyToPasteboard(mergedText)
                            } label: {
                                Label("复制", systemImage: "doc.on.doc").font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.vitrine)
                            Button {
                                writeError = nil; writeResult = nil
                                do {
                                    let path = try MemoryManager.write(mergedText, to: targetPath, append: appendMode)
                                    withAnimation { writeResult = path }
                                } catch {
                                    withAnimation { writeError = error.localizedDescription }
                                }
                            } label: {
                                Label("写入目标（自动备份）", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.vitrineProminent)
                        }
                        if let r = writeResult {
                            Label(r, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10)).foregroundStyle(V.teal).lineLimit(2)
                        }
                        if let e = writeError {
                            Label(e, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 10)).foregroundStyle(V.rose).lineLimit(2)
                        }
                    }
                }

                SectionHeader(title: "预览", subtitle: "Markdown 与 LaTeX 已渲染", icon: "doc.richtext", iconColor: theme.accent1)
                ScrollView {
                    RichText(text: mergedText, size: 12, textColor: theme.textStrong)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .scrollIndicators(.never)
                .vitrineGlass(corner: 14)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 16)
    }

    private var mergedText: String {
        MemoryManager.merged(picked, targetName: (targetPath as NSString).lastPathComponent)
    }

    private func typeColor(_ t: String) -> Color {
        switch t {
        case "user": V.sky
        case "feedback": V.amber
        case "project": V.violet
        case "reference": V.teal
        default: .secondary
        }
    }
}

private struct SourceRow: View {
    @Environment(ThemeManager.self) private var theme
    var source: MemorySource
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: source.kind.agent.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(source.kind.agent.color)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text("\(source.sizeBytes / 1024)KB · \(Fmt.relative(source.modifiedAt))")
                        .font(.system(size: 10)).foregroundStyle(V.textDim)
                }
                Spacer()
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if selected {
                theme.selectionFill(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if hovering {
                RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.05))
            }
        }
        .onHover { hovering = $0 }
    }
}

private struct MemoryItemCard: View {
    var item: MemoryItem
    var added: Bool
    var toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    GlassChip(text: item.type, color: .secondary)
                    Text(item.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(added ? V.teal : V.textDim)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(item.body)
                    .font(.system(size: 10.5))
                    .foregroundStyle(V.textDim)
                    .lineLimit(3)
            }
            .padding(12)
            .contentShape(.rect)
        }
        .pressable(0.98)
        .glassEffect(.regular.tint(added ? V.teal.opacity(0.12) : (hovering ? .primary.opacity(0.06) : .clear)),
                     in: .rect(cornerRadius: 14))
        .onHover { hovering = $0 }
    }
}
