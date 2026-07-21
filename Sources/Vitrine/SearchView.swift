import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @State private var query = ProcessInfo.processInfo.environment["VITRINE_QUERY"] ?? ""
    @State private var agentFilter: AgentKind?
    @State private var hits: [SearchHit] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var visibleHits: [SearchHit] {
        guard !store.showLowSignal else { return hits }
        return hits.filter { store.session($0.sessionId).map { !$0.isLowSignal } ?? true }
    }
    private var hiddenHitCount: Int {
        hits.filter { store.session($0.sessionId)?.isLowSignal ?? false }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("检索")
                    .themedDisplay(24)
                Text("跨 Agent 全文检索所有会话的提问与总结 · FTS5 三元组索引，中文友好")
                    .font(.system(size: 12)).foregroundStyle(V.textDim)
            }
            .padding(.top, 26)

            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(V.textDim)
                TextField("搜索会话内容，例如「triton」「记账」「debate」…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onAppear { focused = true }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(V.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .vitrineGlass(corner: 16)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.accent1.opacity(focused ? 0.8 : 0), lineWidth: 1.5))
            .animation(.easeOut(duration: 0.15), value: focused)

            // Agent filter chips
            HStack(spacing: 6) {
                FilterChip(label: "全部", color: theme.accent1, active: agentFilter == nil) { agentFilter = nil }
                ForEach([AgentKind.claude, .codex, .gemini, .opencode]) { a in
                    FilterChip(label: a.display, color: a.color, active: agentFilter == a) {
                        agentFilter = agentFilter == a ? nil : a
                    }
                }
                if hiddenHitCount > 0 {
                    FilterChip(label: store.showLowSignal ? "隐藏低信号" : "含 \(hiddenHitCount) 低信号",
                               color: V.amber, active: store.showLowSignal) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { store.showLowSignal.toggle() }
                    }
                }
                Spacer()
                if !visibleHits.isEmpty {
                    Text("\(visibleHits.count) 条结果")
                        .font(.system(size: 11)).foregroundStyle(V.textDim)
                        .contentTransition(.numericText())
                }
            }

            // Results
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                EmptyHint(symbol: "sparkle.magnifyingglass", text: "输入关键词，毫秒级命中所有历史会话")
            } else if visibleHits.isEmpty {
                EmptyHint(symbol: "questionmark.circle",
                          text: hits.isEmpty ? "没有匹配 —— 换个关键词试试" : "只命中了低信号会话 —— 点上方「含低信号」查看")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(visibleHits.enumerated()), id: \.element.id) { i, hit in
                            if let s = store.session(hit.sessionId) {
                                SearchHitRow(hit: hit, session: s)
                                    .appearStagger(min(i, 12), trigger: visibleHits.count, perItem: 0.035)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 22)
        .centeredContent(1200)
        .onChange(of: query) { runSearch() }
        .onChange(of: agentFilter) { runSearch() }
        .onChange(of: store.indexReady) { if !query.isEmpty { runSearch() } }
        .onAppear { if !query.isEmpty { runSearch() } }
    }

    private func runSearch() {
        searchTask?.cancel()
        let q = query, agent = agentFilter
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let idx = store.searchIndex else { return }
            let result = idx.search(q, filter: .init(agent: agent))
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { hits = result }
            }
        }
    }
}

private struct FilterChip: View {
    var label: String
    var color: Color
    var active: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? color : (hovering ? .primary : V.textDim))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .contentShape(.capsule)
        }
        .pressable()
        .background {
            if active {
                Capsule().fill(.white.opacity(0.001))
                    .glassEffect(.regular.tint(color.opacity(0.25)), in: .capsule)
            } else {
                Capsule().strokeBorder(.primary.opacity(hovering ? 0.28 : 0.14), lineWidth: 1)
            }
        }
        .hoverLift(1.04)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

private struct SearchHitRow: View {
    @Environment(\.openSession) private var openSession
    var hit: SearchHit
    var session: SessionRecord
    @State private var hovering = false

    var body: some View {
        Button { openSession(session) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    AgentBadge(agent: session.agent, compact: true)
                    Text(session.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(session.projectName).font(.system(size: 10.5)).foregroundStyle(V.textDim)
                    Text(Fmt.day(session.startedAt)).font(.system(size: 10.5)).foregroundStyle(V.textDim)
                }
                Text(highlighted)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(hovering ? session.agent.color.opacity(0.12) : .clear),
                     in: .rect(cornerRadius: 16))
        .scaleEffect(hovering ? 1.008 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
        .onHover { hovering = $0 }
    }

    /// snippet uses ⟦…⟧ as match markers; render matches in accent color.
    private var highlighted: AttributedString {
        var out = AttributedString()
        var rest = hit.snippet[...]
        while let open = rest.range(of: "⟦"), let close = rest.range(of: "⟧", range: open.upperBound..<rest.endIndex) {
            out += AttributedString(String(rest[..<open.lowerBound]))
            var match = AttributedString(String(rest[open.upperBound..<close.lowerBound]))
            match.foregroundColor = V.teal
            match.font = .system(size: 11.5, weight: .bold)
            out += match
            rest = rest[close.upperBound...]
        }
        out += AttributedString(String(rest))
        return out
    }
}
