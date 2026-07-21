import SwiftUI
import Charts

struct ProjectsView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedPath: String?
    @State private var filter = ""
    @FocusState private var filterFocused: Bool

    private var filtered: [ProjectAggregate] {
        guard !filter.isEmpty else { return store.projects }
        return store.projects.filter {
            $0.name.localizedCaseInsensitiveContains(filter) ||
            $0.path.localizedCaseInsensitiveContains(filter)
        }
    }

    private var selected: ProjectAggregate? {
        if let path = selectedPath { return store.projects.first { $0.path == path } }
        if let hint = ProcessInfo.processInfo.environment["VITRINE_PROJECT"],
           let m = store.projects.first(where: { $0.name.contains(hint) || $0.path.contains(hint) }) {
            return m
        }
        return store.projects.first
    }

    var body: some View {
        HStack(spacing: 0) {
            // Project list
            VStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(V.textDim)
                    TextField("过滤项目…", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($filterFocused)
                    if !filter.isEmpty {
                        Button { filter = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(V.textDim)
                        }.buttonStyle(.plain)
                    }
                }
                .vitrineField(focused: filterFocused, corner: 20)
                .padding(.top, 26)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, p in
                            ProjectListRow(project: p, selected: selected?.path == p.path) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    selectedPath = p.path
                                }
                            }
                            .appearStagger(i, trigger: filter)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .padding(.horizontal, 14)
            .frame(minWidth: 220, idealWidth: 270, maxWidth: 320)

            Divider().opacity(0.15)

            if let p = selected {
                ProjectDetail(project: p)
                    .id(p.path)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            } else {
                EmptyHint(symbol: "square.stack.3d.up", text: "选择一个项目")
            }
        }
    }
}

private struct ProjectListRow: View {
    @Environment(ThemeManager.self) private var theme
    var project: ProjectAggregate
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(project.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach(project.agents) { a in
                            Circle().fill(a.color).frame(width: 6, height: 6)
                        }
                    }
                }
                HStack {
                    Text("\(project.sessions.count) 会话 · 活跃 \(project.activeDays) 天")
                        .font(.system(size: 10)).foregroundStyle(V.textDim)
                    Spacer()
                    Text(Fmt.relative(project.lastActivity))
                        .font(.system(size: 10)).foregroundStyle(V.textDim)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if selected {
                theme.selectionFill(RoundedRectangle(cornerRadius: 13, style: .continuous))
            } else if hovering {
                RoundedRectangle(cornerRadius: 13).fill(.primary.opacity(0.05))
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Project detail with multi-perspective visualizations

private enum Perspective: String, CaseIterable, Identifiable {
    case braid = "织线", heat = "热力", mix = "构成", rhythm = "节律", insight = "AI 洞察"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .braid: "point.topleft.down.to.point.bottomright.curvepath"
        case .heat: "square.grid.4x3.fill"
        case .mix: "chart.pie"
        case .rhythm: "waveform.path.ecg"
        case .insight: "sparkles"
        }
    }
}

private struct ProjectDetail: View {
    @Environment(AppStore.self) private var store
    var project: ProjectAggregate
    @State private var perspective: Perspective = {
        if let raw = ProcessInfo.processInfo.environment["VITRINE_PERSPECTIVE"],
           let p = Perspective.allCases.first(where: { $0.rawValue == raw || "\($0)" == raw }) { return p }
        return .braid
    }()
    @Namespace private var pickerNS

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                // Perspective picker (glass pill)
                HStack(spacing: 4) {
                    ForEach(Perspective.allCases) { p in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { perspective = p }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: p.symbol).font(.system(size: 10, weight: .semibold))
                                Text(p.rawValue).font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 13).padding(.vertical, 7)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(perspective == p ? .primary : V.textDim)
                        .background {
                            if perspective == p {
                                Capsule()
                                    .fill(.white.opacity(0.001))
                                    .vitrineGlassCapsule()
                                    .matchedGeometryEffect(id: "perspective", in: pickerNS)
                            }
                        }
                    }
                }
                .padding(4)
                .vitrineGlassCapsule(tintStrength: 0.4)

                perspectiveBody
                    .transition(.opacity.combined(with: .offset(y: 8)))
                    .id(perspective)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: perspective)

                // Chronological sessions with gap markers
                GlassCard(padding: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionHeader(title: "贡献流",
                                      subtitle: "跨 Agent 按时间排布 · 灰色标记为 7 天以上的中断",
                                      icon: "chart.line.uptrend.xyaxis", iconColor: V.violet)
                            .padding(8)
                        contributionFlow
                    }
                }
            }
            .padding(22)
            .centeredContent(1180)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private var perspectiveBody: some View {
        switch perspective {
        case .braid:
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "织线视图", subtitle: "每条泳道一个 Agent，胶囊为一次会话 — 贡献不连续处即空隙", icon: "chart.bar.doc.horizontal.fill", iconColor: V.teal)
                    LaneTimeline(project: project)
                }
            }
        case .heat:
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "热力视图", subtitle: "该项目的每日消息量", icon: "square.grid.3x3.fill", iconColor: V.violet)
                    HeatmapGrid(activity: project.sessions.dailyActivity(), accent: V.violet)
                }
            }
        case .mix:
            HStack(alignment: .top, spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Agent 占比", subtitle: "按消息量", icon: "chart.pie.fill", iconColor: V.teal)
                        AgentDonut(share: project.agentShare)
                    }
                }
                .frame(minWidth: 260, maxWidth: 360)
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "模型使用", subtitle: "出现该模型的会话数", icon: "cpu.fill", iconColor: V.sky)
                        ModelBarChart(sessions: project.sessions)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        case .rhythm:
            RhythmView(sessions: project.sessions)
        case .insight:
            ProjectInsightPanel(project: project)
        }
    }

    private var contributionFlow: some View {
        let ordered = project.sessions.sorted { $0.startedAt > $1.startedAt }
        return ForEach(Array(ordered.enumerated()), id: \.element.id) { i, s in
            VStack(spacing: 2) {
                if i > 0 {
                    let prev = ordered[i - 1]
                    let gap = prev.startedAt.timeIntervalSince(s.endedAt)
                    if gap > 7 * 86400 {
                        HStack(spacing: 8) {
                            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
                            Text("中断 \(Int(gap / 86400)) 天")
                                .font(.system(size: 9.5)).foregroundStyle(V.textDim)
                                .fixedSize()
                            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 5)
                    }
                }
                SessionRow(session: s, showProject: false)
            }
            .appearStagger(min(i, 16), trigger: project.path, baseDelay: 0.05, perItem: 0.03)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.name)
                    .themedDisplay(22)
                Spacer()
                batchSummarizeButton
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
                } label: {
                    Label("Finder", systemImage: "folder")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.vitrine)
            }
            Text(project.path)
                .font(.vMono)
                .foregroundStyle(V.textDim)
            HStack(spacing: 8) {
                GlassChip(text: "\(project.sessions.count) 会话", color: V.teal, systemImage: "bubble.left.and.bubble.right")
                GlassChip(text: "活跃 \(project.activeDays)/\(project.spanDays) 天", color: V.violet, systemImage: "calendar")
                GlassChip(text: Fmt.tokens(project.totalTokens) + " tok", color: V.amber, systemImage: "bolt")
                ForEach(project.agents) { a in
                    AgentBadge(agent: a, compact: true)
                }
            }
        }
        .padding(.top, 26)
    }

    @ViewBuilder
    private var batchSummarizeButton: some View {
        let pending = project.sessions.filter { store.summaries[$0.id] == nil }.count
        if store.batchSummarizing {
            Button { store.cancelBatch() } label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("总结中 \(store.batchDone)/\(store.batchTotal)")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(.vitrine)
        } else if store.aiAvailable && pending > 0 {
            Button {
                let sessions = project.sessions
                Task { await store.batchSummarize(sessions) }
            } label: {
                Label("批量总结 \(pending)", systemImage: "wand.and.stars")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.vitrine)
            .help("对该项目所有未总结的会话批量生成 AI 总结")
        }
    }
}

/// Per-project model usage as horizontal bars — hover (or focus) a bar to spotlight it; the rest
/// dim and its count enlarges. Distinct qualitative colors so each model stands apart.
private struct ModelBarChart: View {
    var sessions: [SessionRecord]
    @State private var sel: String?

    private var counts: [(model: String, n: Int, color: Color)] {
        var acc: [String: Int] = [:]
        for s in sessions {
            for raw in Set(s.models) {
                let l = ModelInfo.label(raw)
                if !l.isEmpty { acc[l, default: 0] += 1 }
            }
        }
        return acc.sorted { $0.value > $1.value }.prefix(10).enumerated().map { i, kv in
            (kv.key, kv.value, ChartColors.at(i))
        }
    }

    var body: some View {
        let data = counts
        Chart(data, id: \.model) { item in
            BarMark(x: .value("会话", item.n), y: .value("模型", item.model))
                .cornerRadius(4)
                .foregroundStyle(item.color.gradient)
                .opacity(sel == nil || sel == item.model ? 1 : 0.28)
                .annotation(position: .trailing) {
                    Text("\(item.n)")
                        .font(.system(size: sel == item.model ? 11 : 9,
                                      weight: sel == item.model ? .bold : .regular,
                                      design: .rounded))
                        .foregroundStyle(sel == item.model ? item.color : V.textDim)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel().font(.system(size: 9.5,
                                              weight: (value.as(String.self) == sel) ? .bold : .regular))
            }
        }
        .chartYSelection(value: $sel)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: sel)
        .frame(height: max(120, CGFloat(data.count) * 26))
    }
}
