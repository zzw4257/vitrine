import SwiftUI

/// The per-project AI "secondary summary": an overview + milestone timeline generated on demand.
/// It sits alongside the static perspectives and never replaces them — the static analysis
/// (织线/热力/构成/节律) remains the ground truth; this is an interpretive layer on top.
struct ProjectInsightPanel: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @Environment(UIState.self) private var ui
    var project: ProjectAggregate

    @State private var generating = false
    @State private var error: String?
    @State private var didAutoGen = false

    private var insight: ProjectInsight? { store.insights[project.path] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controlBar
            if let e = error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5)).foregroundStyle(V.rose)
            }
            if let insight {
                overviewCard(insight)
                    .appearStagger(0, trigger: insight.generatedAt)
                if !insight.timeline.isEmpty {
                    timelineCard(insight).appearStagger(1, trigger: insight.generatedAt)
                }
                if !insight.highlights.isEmpty {
                    highlightsCard(insight).appearStagger(2, trigger: insight.generatedAt)
                }
            } else if !generating {
                emptyState
            }
        }
        .onAppear { maybeAutoGen() }
        .onChange(of: store.cliTools.count) { maybeAutoGen() }
    }

    private func maybeAutoGen() {
        guard !didAutoGen, insight == nil,
              let hint = ProcessInfo.processInfo.environment["VITRINE_GEN_INSIGHT"],
              project.name.contains(hint) || project.path.contains(hint),
              store.aiAvailable else { return }
        didAutoGen = true
        generate()
    }

    // MARK: control bar

    private var controlBar: some View {
        GlassCard(tint: theme.accent1, padding: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("AI 二次总结", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accentGradient)
                    if let insight {
                        Text("由 \(insight.model) 生成 · \(Fmt.relative(insight.generatedAt)) · 基于静态事实，不改动原始分析")
                            .font(.system(size: 10.5)).foregroundStyle(V.textDim)
                    } else {
                        Text("用所选模型分析该项目的全部会话，生成概述与阶段时间线")
                            .font(.system(size: 10.5)).foregroundStyle(V.textDim)
                    }
                }
                Spacer()
                if store.aiAvailable {
                    modelBadge
                    Button {
                        generate()
                    } label: {
                        HStack(spacing: 6) {
                            if generating { ProgressView().controlSize(.small) }
                            else { Image(systemName: insight == nil ? "wand.and.stars" : "arrow.clockwise") }
                            Text(insight == nil ? "生成洞察" : "重新生成")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                    }
                    .buttonStyle(.vitrineProminent)
                    .disabled(generating)
                } else {
                    Button { ui.showSettings = true } label: {
                        Label("配置 AI", systemImage: "gearshape")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.vitrine)
                }
            }
        }
    }

    private var modelBadge: some View {
        let ai = store.ai
        return GlassChip(
            text: ai.isLocalClaude ? "Claude CLI" : (ai.model.isEmpty ? ai.provider.name : ai.model),
            color: theme.accent2,
            systemImage: ai.isLocalClaude ? "terminal" : "cloud")
    }

    // MARK: cards

    private func overviewCard(_ i: ProjectInsight) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "概述", icon: "text.alignleft", iconColor: theme.accent1)
                RichText(text: i.overview, size: 13, textColor: theme.textStrong)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func timelineCard(_ i: ProjectInsight) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "演进时间线", subtitle: "AI 归纳的阶段（非逐会话）")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(i.timeline.enumerated()), id: \.element.id) { idx, m in
                        TimelineRow(milestone: m, isLast: idx == i.timeline.count - 1)
                            .appearStagger(idx, trigger: i.generatedAt, baseDelay: 0.1, perItem: 0.08)
                    }
                }
            }
        }
    }

    private func highlightsCard(_ i: ProjectInsight) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "关键点")
                ForEach(Array(i.highlights.enumerated()), id: \.offset) { idx, h in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5)).foregroundStyle(theme.accent2)
                            .padding(.top, 6)
                        RichText(text: h, size: 12, textColor: theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .appearStagger(idx, trigger: i.generatedAt, baseDelay: 0.2, perItem: 0.05)
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(theme.accentGradient)
                Text(store.aiAvailable
                     ? "还没有 AI 洞察 —— 点击右上角「生成洞察」"
                     : "先在设置里配置 AI 服务商，再生成洞察")
                    .font(.system(size: 12)).foregroundStyle(V.textDim)
                Text("该组件是对静态分析的补充解读，随时可重新生成，不影响其它视角")
                    .font(.system(size: 10.5)).foregroundStyle(V.textDim.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func generate() {
        generating = true; error = nil
        Task {
            do { try await store.generateInsight(for: project) }
            catch { await MainActor.run { self.error = error.localizedDescription } }
            await MainActor.run { generating = false }
        }
    }
}

private struct TimelineRow: View {
    @Environment(ThemeManager.self) private var theme
    var milestone: InsightMilestone
    var isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                if !isLast {
                    Rectangle()
                        .fill(theme.accent1.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 11)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(milestone.title).font(.system(size: 12.5, weight: .semibold))
                    if !milestone.date.isEmpty {
                        GlassChip(text: milestone.date, color: theme.accent2)
                    }
                }
                RichText(text: milestone.detail, size: 11.5, textColor: theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, isLast ? 0 : 14)
            }
        }
    }
}
