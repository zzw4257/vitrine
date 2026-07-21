import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var composition = ProcessInfo.processInfo.environment["VITRINE_COMPOSITION"] == "model" ? 1 : 0   // 0 = agents, 1 = models
    @State private var metric: ShareMetric = .messages
    @AppStorage("vitrine.sessionLayout") private var sessionLayout: SessionLayout = .list
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var recentSessions: [SessionRecord] {
        let base = store.showLowSignal ? store.sessions : store.sessions.filter { !$0.isLowSignal }
        return Array(base.prefix(sessionLayout == .list ? 9 : 15))
    }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                // Stat tiles — adaptive columns wide enough to fill evenly (≈5 at full width,
                // wrapping to fewer rows as the window narrows) instead of clustering left.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    let intFmt: (Double) -> String = { "\(Int($0.rounded()))" }
                    let tokFmt: (Double) -> String = { Fmt.tokens(Int($0.rounded())) }
                    StatTile(title: "项目", value: "\(store.projects.count)",
                             symbol: "square.stack.3d.up", color: V.violet,
                             numericValue: Double(store.projects.count), format: intFmt)
                        .appearStagger(0, trigger: store.sessions.count)
                    StatTile(title: "会话", value: "\(store.sessions.count)",
                             symbol: "bubble.left.and.bubble.right", color: V.teal,
                             numericValue: Double(store.sessions.count), format: intFmt)
                        .appearStagger(1, trigger: store.sessions.count)
                    StatTile(title: "消息", value: Fmt.tokens(store.sessions.totalMessages),
                             symbol: "text.alignleft", color: V.sky,
                             numericValue: Double(store.sessions.totalMessages), format: tokFmt)
                        .appearStagger(2, trigger: store.sessions.count)
                    StatTile(title: "总吞吐 tokens", value: Fmt.tokens(store.sessions.totalTokens),
                             symbol: "bolt", color: V.amber,
                             numericValue: Double(store.sessions.totalTokens), format: tokFmt)
                        .appearStagger(3, trigger: store.sessions.count)
                    StatTile(title: "活跃天数", value: "\(store.sessions.dailyActivity().count)",
                             symbol: "calendar", color: V.rose,
                             numericValue: Double(store.sessions.dailyActivity().count), format: intFmt)
                        .appearStagger(4, trigger: store.sessions.count)
                }

                // Activity heatmap
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SectionHeader(title: "半年活跃热力", subtitle: "全部 Agent 的每日消息量", icon: "calendar", iconColor: V.rose)
                            Spacer()
                            Toggle("含子代理", isOn: $store.includeSubagents)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .font(.system(size: 11))
                                .foregroundStyle(V.textDim)
                        }
                        HeatmapGrid(activity: store.sessions.dailyActivity())
                    }
                }
                .appearStagger(5, trigger: store.sessions.count)

                // Composition + top projects
                HStack(alignment: .top, spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                SectionHeader(title: composition == 0 ? "Agent 构成" : "模型分布",
                                              subtitle: metric.subtitle, icon: "chart.pie.fill", iconColor: V.teal)
                                Spacer()
                                Picker("", selection: $composition) {
                                    Text("Agent").tag(0)
                                    Text("模型").tag(1)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 128)
                            }
                            Picker("", selection: $metric) {
                                ForEach(ShareMetric.allCases) { Text($0.display).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Group {
                                if composition == 0 {
                                    if globalShare.isEmpty {
                                        EmptyHint(symbol: "chart.pie", text: "暂无数据").frame(height: 140)
                                    } else {
                                        AgentDonut(share: globalShare)
                                    }
                                } else {
                                    if globalModelShare.isEmpty {
                                        EmptyHint(symbol: "cpu",
                                                  text: metric == .tokens ? "这些会话没有 token 计量" : "会话尚未记录模型信息")
                                            .frame(height: 140)
                                    } else {
                                        ModelDonut(share: globalModelShare)
                                    }
                                }
                            }
                            .id("\(composition)-\(metric.rawValue)")
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: composition)
                            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: metric)
                        }
                    }
                    .frame(minWidth: 280, maxWidth: 360)
                    .appearStagger(6, trigger: store.sessions.count)

                    GlassCard(padding: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "最活跃项目", icon: "star.fill", iconColor: V.amber).padding(8)
                            ForEach(Array(store.projects.prefix(5).enumerated()), id: \.element.id) { i, p in
                                TopProjectRow(project: p)
                                    .appearStagger(i, trigger: store.projects.count, baseDelay: 0.35, perItem: 0.04)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .appearStagger(7, trigger: store.sessions.count)
                }

                // Recent sessions
                GlassCard(padding: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            SectionHeader(title: "最近会话", icon: "clock.fill", iconColor: V.sky)
                            if store.hiddenLowSignalCount > 0 {
                                Button {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                        store.showLowSignal.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: store.showLowSignal ? "eye.slash.fill" : "line.3.horizontal.decrease.circle")
                                        Text(store.showLowSignal
                                             ? "隐藏 \(store.hiddenLowSignalCount) 条低信号"
                                             : "已隐 \(store.hiddenLowSignalCount) 条低信号")
                                    }
                                    .font(.system(size: 10.5, weight: .medium))
                                }
                                .buttonStyle(.vitrine)
                                .help("默认屏蔽 Vitrine 自动生成的总结/蒸馏会话与极小会话")
                            }
                            Spacer()
                            Picker("", selection: $sessionLayout) {
                                ForEach(SessionLayout.allCases) { l in
                                    Image(systemName: l.icon).tag(l)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 116)
                            .help("列表 · 瀑布 · 方格")
                        }
                        .padding(.horizontal, 8).padding(.top, 4)

                        SessionGallery(sessions: recentSessions, layout: sessionLayout)
                            .padding(.horizontal, sessionLayout == .list ? 0 : 8)
                            .padding(.bottom, sessionLayout == .list ? 0 : 8)
                            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sessionLayout)
                    }
                }
                .appearStagger(8, trigger: store.sessions.count)
            }
            .padding(22)
            .centeredContent()
        }
        .scrollIndicators(.never)
    }

    private var globalShare: [(agent: AgentKind, messages: Int)] {
        store.sessions.agentShare(by: metric)
    }

    private var globalModelShare: [(label: String, value: Int, color: Color)] {
        store.sessions.modelShare(by: metric)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("总览")
                .themedDisplay(24)
            Text("你的全部 Agent 工作，一览无余 · 最近扫描 \(store.lastScan.map(Fmt.relative) ?? "—")")
                .font(.system(size: 12))
                .foregroundStyle(V.textDim)
        }
        .padding(.top, 26)
    }
}

private struct TopProjectRow: View {
    @Environment(AppStore.self) private var store
    var project: ProjectAggregate
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(V.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(project.path)
                    .font(.system(size: 10)).foregroundStyle(V.textDim).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(project.agents) { a in
                    Circle().fill(a.color)
                        .frame(width: hovering ? 9 : 7, height: hovering ? 9 : 7)
                }
            }
            Text("\(project.sessions.count) 会话")
                .font(.system(size: 10.5)).foregroundStyle(V.textDim)
            Text(Fmt.relative(project.lastActivity))
                .font(.system(size: 10.5)).foregroundStyle(V.textDim)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 12))
        .hoverLift(1.01)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hovering = h } }
    }
}
