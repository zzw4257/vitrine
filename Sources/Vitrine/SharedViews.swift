import SwiftUI
import Charts

// MARK: - Agent badge

struct AgentBadge: View {
    var agent: AgentKind
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: agent.symbol)
                .font(.system(size: compact ? 8 : 10, weight: .bold))
            if !compact {
                Text(agent.display).font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(agent.color)
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(agent.color.opacity(0.14), in: .capsule)
        .overlay(Capsule().strokeBorder(agent.color.opacity(0.3), lineWidth: 0.5))
    }
}

// MARK: - Session row

struct SessionRow: View {
    @Environment(\.openSession) private var openSession
    @Environment(ThemeManager.self) private var theme
    var session: SessionRecord
    var showProject = true
    @State private var hovering = false

    private var accent: Color { session.agent.color }
    private var modelLabel: String? {
        guard let raw = session.models.first else { return nil }
        let l = ModelInfo.label(raw); return l.isEmpty ? nil : l
    }

    var body: some View {
        Button { openSession(session) } label: {
            HStack(spacing: 11) {
                // Agent glyph tile — a solid, branded anchor instead of a hairline bar.
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(accent.opacity(hovering ? 0.24 : 0.15))
                    Image(systemName: session.agent.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                        .symbolEffect(.bounce, value: hovering)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.textStrong)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if showProject {
                            Label(session.projectName, systemImage: "folder")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 10)).foregroundStyle(V.textDim)
                                .lineLimit(1)
                        }
                        if let m = modelLabel {
                            Text(m).font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(ModelInfo.vendorColor(m).opacity(0.9))
                                .lineLimit(1)
                        }
                        if session.isSubagent { GlassChip(text: "子", color: .gray) }
                    }
                }

                Spacer(minLength: 8)

                // Right cluster fills the old blank space with real signal.
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Fmt.relative(session.startedAt))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(V.textDim)
                    HStack(spacing: 5) {
                        metricPill("bubble.left.and.bubble.right", "\(session.messageCount)")
                        if session.totalTokens > 0 {
                            metricPill("bolt.fill", Fmt.tokens(session.totalTokens))
                        }
                    }
                    .opacity(hovering ? 1 : 0.82)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(.rect)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(hovering ? 0.09 : 0))
            }
            .overlay(alignment: .leading) {
                Capsule().fill(accent)
                    .frame(width: 2.5, height: hovering ? 26 : 0)
                    .padding(.leading, 1)
            }
        }
        .pressable(0.985)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hovering = h } }
    }

    private func metricPill(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 7.5))
            Text(text).font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(V.textDim)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(theme.well.opacity(0.6), in: .capsule)
    }
}

// MARK: - GitHub-style activity heatmap

struct HeatmapGrid: View {
    @Environment(ThemeManager.self) private var theme
    var activity: [Date: Int]
    var minWeeks: Int = 26
    var accent: Color = V.teal
    @State private var hoverDay: Date?
    @State private var hoverCount = 0
    @State private var hoverPoint: CGPoint = .zero

    private var maxValue: Int { max(1, activity.values.max() ?? 1) }
    private let weekdayLabels = ["日", "一", "二", "三", "四", "五", "六"]

    /// Color for a cell given its 0…1 intensity — GitHub uses discrete greens, others fade the accent.
    private func heatColor(_ intensity: Double) -> Color {
        guard let ramp = theme.palette.heatRamp, !ramp.isEmpty else {
            return accent.opacity(0.25 + 0.75 * intensity)
        }
        let idx = min(ramp.count - 1, max(0, Int(intensity * Double(ramp.count - 1) + 0.5)))
        return ramp[idx]
    }

    var body: some View {
        GeometryReader { geo in
            let labelW: CGFloat = 20        // left gutter for weekday labels
            let gap: CGFloat = 3
            let cellCap: CGFloat = 20
            // Fill the available width: grow the number of weeks (history depth) so the grid
            // never leaves an awkward empty band on wide/fullscreen windows.
            let fitWeeks = Int((geo.size.width - labelW + gap) / (cellCap + gap))
            let weeks = max(minWeeks, min(53, fitWeeks))
            let cols = CGFloat(weeks)
            let cell = min(cellCap, (geo.size.width - labelW - (cols - 1) * gap) / cols)
            let step = cell + gap
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let weekday = cal.component(.weekday, from: today) - 1  // 0=Sun

            // Map a pointer position back to the day cell under it (mirrors the draw math).
            let cellAt: (CGPoint) -> (Date, Int)? = { p in
                let w = Int((p.x - labelW) / step)
                let d = Int((p.y - 16) / step)
                guard w >= 0, w < weeks, d >= 0, d < 7 else { return nil }
                let daysAgo = (weeks - 1 - w) * 7 + (weekday - d)
                guard daysAgo >= 0, let day = cal.date(byAdding: .day, value: -daysAgo, to: today) else { return nil }
                return (day, activity[day] ?? 0)
            }

            ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                // Month labels across the top
                var lastMonth = -1
                for w in 0..<weeks {
                    let daysAgo = (weeks - 1 - w) * 7 + weekday
                    guard let colDate = cal.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
                    let m = cal.component(.month, from: colDate)
                    if m != lastMonth {
                        lastMonth = m
                        ctx.draw(
                            Text("\(m)月").font(.system(size: 8.5)).foregroundStyle(.secondary),
                            at: CGPoint(x: labelW + CGFloat(w) * step, y: 6), anchor: .leading)
                    }
                }
                // Weekday labels (show Mon/Wed/Fri)
                for d in [1, 3, 5] {
                    ctx.draw(
                        Text(weekdayLabels[d]).font(.system(size: 8)).foregroundStyle(.secondary),
                        at: CGPoint(x: labelW - 6, y: 16 + CGFloat(d) * step + cell / 2), anchor: .trailing)
                }
                // Cells
                for w in 0..<weeks {
                    for d in 0..<7 {
                        let daysAgo = (weeks - 1 - w) * 7 + (weekday - d)
                        guard daysAgo >= 0 else { continue }
                        guard let day = cal.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
                        let v = activity[day] ?? 0
                        let ratio = min(1.0, Double(v) / Double(maxValue))
                        let rect = CGRect(x: labelW + CGFloat(w) * step, y: 16 + CGFloat(d) * step,
                                          width: cell, height: cell)
                        let path = Path(roundedRect: rect, cornerRadius: 3)
                        if v == 0 {
                            ctx.fill(path, with: .color(.primary.opacity(0.06)))
                        } else {
                            ctx.fill(path, with: .color(heatColor(ratio)))
                        }
                        // Today: bright ring so "现在" is unmistakable
                        if daysAgo == 0 {
                            ctx.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 4),
                                       with: .color(.primary.opacity(0.85)), lineWidth: 1.5)
                        }
                        // Hovered cell: accent ring
                        if let hd = hoverDay, cal.isDate(day, inSameDayAs: hd) {
                            ctx.stroke(Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 4),
                                       with: .color(accent), lineWidth: 2)
                        }
                    }
                }
            }
            .frame(height: 16 + 7 * step)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    if let (day, c) = cellAt(p) { hoverDay = day; hoverCount = c; hoverPoint = p }
                    else { hoverDay = nil }
                case .ended: hoverDay = nil
                }
            }

            if let hd = hoverDay {
                HStack(spacing: 5) {
                    Text(Fmt.day(hd)).font(.system(size: 10, weight: .semibold))
                    Text(hoverCount == 0 ? "无活动" : "\(hoverCount) 条消息")
                        .font(.system(size: 10)).foregroundStyle(hoverCount == 0 ? V.textDim : accent)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
                .fixedSize()
                .position(x: min(max(hoverPoint.x, 52), geo.size.width - 52),
                          y: max(hoverPoint.y - 20, 8))
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hoverDay)
        }
        .frame(height: 185)
        .overlay(alignment: .bottomTrailing) { legend }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("今天").font(.system(size: 8.5)).foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.8), lineWidth: 1.5)
                .frame(width: 11, height: 11)
            Text("少").font(.system(size: 8.5)).foregroundStyle(.secondary).padding(.leading, 4)
            ForEach([-1.0, 0.0, 0.34, 0.67, 1.0], id: \.self) { o in
                RoundedRectangle(cornerRadius: 2)
                    .fill(o < 0 ? Color.primary.opacity(0.06) : heatColor(o))
                    .frame(width: 11, height: 11)
            }
            Text("多").font(.system(size: 8.5)).foregroundStyle(.secondary)
        }
        .padding(.trailing, 2)
    }
}

// MARK: - Composition donut (agents / models)

struct DonutSlice: Identifiable {
    var label: String
    var value: Int
    var color: Color
    var id: String { label }
}

/// Generic slice donut with a spin-in draw, an interactive legend, and a live center readout.
/// Hover (or drag) the ring, or hover/click a legend row: the focused slice pops out, the rest
/// dim, and the hole shows that slice's share. Backs the agent + model composition charts.
struct SliceDonut: View {
    var slices: [DonutSlice]
    var keyspace: String = "donut"
    @State private var reveal = false
    @State private var hovered: String?
    @State private var pinned: String?
    @State private var sel: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: String? { hovered ?? pinned ?? labelAt(sel) }
    private var total: Int { max(1, slices.reduce(0) { $0 + $1.value }) }

    /// Map the angular-selection value (position along the summed domain) to a slice label.
    private func labelAt(_ v: Int?) -> String? {
        guard let v else { return nil }
        var acc = 0
        for s in slices { acc += s.value; if v < acc { return s.label } }
        return slices.last?.label
    }
    private func pct(_ v: Int) -> String {
        let p = Double(v) / Double(total) * 100
        return p >= 0.5 ? "\(Int(p.rounded()))%" : (p > 0 ? "<1%" : "0%")
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Chart(slices) { item in
                    SectorMark(
                        angle: .value("v", item.value),
                        innerRadius: .ratio(0.62),
                        outerRadius: .ratio(active == item.label ? 1.0 : (active == nil ? 0.93 : 0.83)),
                        angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(item.color.gradient)
                    .opacity(active == nil || active == item.label ? 1 : 0.26)
                }
                .chartAngleSelection(value: $sel)
                .chartLegend(.hidden)
                .frame(width: 134, height: 134)
                .animation(.spring(response: 0.34, dampingFraction: 0.72), value: active)

                VStack(spacing: 1) {
                    if let a = active, let s = slices.first(where: { $0.label == a }) {
                        Text(pct(s.value))
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(s.color)
                        Text(a).font(.system(size: 9)).foregroundStyle(V.textDim)
                            .lineLimit(1).frame(maxWidth: 86)
                    } else {
                        Text("\(slices.count)").font(.system(size: 21, weight: .bold, design: .rounded))
                        Text(keyspace == "model" ? "个模型" : "个 Agent")
                            .font(.system(size: 9)).foregroundStyle(V.textDim)
                    }
                }
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3), value: active)
            }
            .scaleEffect(reveal ? 1 : 0.7)
            .rotationEffect(.degrees(reveal || reduceMotion ? 0 : -90))
            .opacity(reveal ? 1 : 0)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { i, item in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            pinned = (pinned == item.label) ? nil : item.label
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Circle().fill(item.color).frame(width: 8, height: 8)
                                .scaleEffect(active == item.label ? 1.45 : 1)
                            Text(item.label)
                                .font(.system(size: 11.5, weight: active == item.label ? .bold : .medium))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            CountingText(value: Double(item.value) / Double(total) * 100,
                                         format: { $0 >= 0.5 ? "\(Int($0.rounded()))%" : ($0 > 0 ? "<1%" : "0%") },
                                         font: .system(size: 11.5, weight: .semibold, design: .rounded),
                                         key: "\(keyspace)-\(item.label)")
                                .foregroundStyle(active == item.label ? item.color : V.textDim)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(active == item.label ? item.color.opacity(0.14) : .clear,
                                    in: .rect(cornerRadius: 6))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? item.label : (hovered == item.label ? nil : hovered) }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
                    .opacity(reveal ? 1 : 0)
                    .offset(x: reveal ? 0 : 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3 + Double(i) * 0.06), value: reveal)
                }
            }
        }
        .onAppear {
            reveal = false
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(reduceMotion ? 0 : 0.15)) { reveal = true }
        }
    }
}

struct AgentDonut: View {
    var share: [(agent: AgentKind, messages: Int)]
    var body: some View {
        SliceDonut(slices: share.map { DonutSlice(label: $0.agent.display, value: $0.messages, color: $0.agent.color) },
                   keyspace: "agent")
    }
}

struct ModelDonut: View {
    var share: [(label: String, value: Int, color: Color)]
    var body: some View {
        SliceDonut(slices: share.map { DonutSlice(label: $0.label, value: $0.value, color: $0.color) },
                   keyspace: "model")
    }
}

// MARK: - Braid timeline (per-agent lanes, non-contiguous sessions visible as gaps)

struct LaneTimeline: View {
    @Environment(\.openSession) private var openSession
    @Environment(ThemeManager.self) private var theme
    var project: ProjectAggregate
    @State private var hovered: String?
    @State private var reveal = false
    @State private var measuredW: CGFloat = 0

    private var range: ClosedRange<Date> {
        let lo = project.firstActivity
        let hi = max(project.lastActivity, lo.addingTimeInterval(3600))
        return lo...hi
    }

    private let labelW: CGFloat = 116
    private let barH: CGFloat = 12
    private let rowStride: CGFloat = 16     // sub-row vertical stride
    private let vpad: CGFloat = 12
    private let minW: CGFloat = 9
    private let capGap: CGFloat = 4         // min horizontal gap before reusing a sub-row

    private struct Placed { let s: SessionRecord; let x: CGFloat; let w: CGFloat; let row: Int }
    private struct Lane { let agent: AgentKind; let top: CGFloat; let height: CGFloat; let placed: [Placed] }

    /// Greedy interval packing: a session drops into the first sub-row whose last capsule ended
    /// before it starts (+gap); otherwise a new sub-row. Eliminates all visual overlap.
    private func pack(_ sessions: [SessionRecord], plotW: CGFloat, span: TimeInterval) -> [Placed] {
        var rowEnds: [CGFloat] = []
        var out: [Placed] = []
        for s in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let sf = max(0.0, min(1.0, s.startedAt.timeIntervalSince(range.lowerBound) / span))
            let df = max(0.0, min(1.0, s.duration / span))
            let x = plotW * CGFloat(sf)
            var w = max(minW, plotW * CGFloat(df))
            if x + w > plotW { w = max(minW, plotW - x) }
            var row = rowEnds.firstIndex { $0 + capGap <= x } ?? -1
            if row < 0 { row = rowEnds.count; rowEnds.append(x + w) } else { rowEnds[row] = x + w }
            out.append(Placed(s: s, x: x, w: w, row: row))
        }
        return out
    }

    private func lanes(plotW: CGFloat, span: TimeInterval) -> [Lane] {
        var top: CGFloat = 0
        var result: [Lane] = []
        for agent in project.agents {
            let placed = pack(project.sessions.filter { $0.agent == agent }, plotW: plotW, span: span)
            let rows = (placed.map(\.row).max() ?? 0) + 1
            let h = max(48, CGFloat(rows) * rowStride + vpad * 2 - (rowStride - barH))
            result.append(Lane(agent: agent, top: top, height: h, placed: placed))
            top += h + 8
        }
        return result
    }

    var body: some View {
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        let plotW = max(10, measuredW - labelW)
        let ls = lanes(plotW: plotW, span: span)
        let contentH = (ls.last.map { $0.top + $0.height } ?? 60)

        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                // Gridlines + now marker span the full content height for a woven feel.
                Canvas { ctx, size in
                    let cal = Calendar.current
                    var tick = cal.dateInterval(of: .month, for: range.lowerBound)?.start ?? range.lowerBound
                    while tick <= range.upperBound {
                        let x = labelW + plotW * CGFloat(tick.timeIntervalSince(range.lowerBound) / span)
                        if x >= labelW {
                            var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height - 15))
                            ctx.stroke(line, with: .color(theme.hairline), lineWidth: 1)
                            ctx.draw(Text(tick.formatted(.dateTime.month(.abbreviated)))
                                .font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary),
                                at: CGPoint(x: x + 3, y: size.height - 6), anchor: .leading)
                        }
                        tick = cal.date(byAdding: .month, value: 1, to: tick) ?? range.upperBound.addingTimeInterval(1)
                    }
                    let nx = labelW + plotW
                    var nl = Path(); nl.move(to: CGPoint(x: nx, y: 0)); nl.addLine(to: CGPoint(x: nx, y: size.height - 15))
                    ctx.stroke(nl, with: .color(theme.accent2.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                .frame(height: contentH)

                ForEach(Array(ls.enumerated()), id: \.element.agent) { i, lane in
                    // Lane container (subtle) groups its sub-rows.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.hoverBg.opacity(i % 2 == 0 ? 0.55 : 0.30))
                        .frame(width: max(0, plotW), height: lane.height - 4)
                        .position(x: labelW + plotW / 2, y: lane.top + lane.height / 2)
                    laneLabel(lane.agent)
                        .position(x: (labelW - 8) / 2 + 2, y: lane.top + lane.height / 2)
                    ForEach(lane.placed, id: \.s.id) { p in
                        capsuleView(p, lane: lane, plotW: plotW)
                    }
                }
            }
            .frame(height: contentH)
            .background(GeometryReader { g in
                Color.clear.onAppear { measuredW = g.size.width }
                    .onChange(of: g.size.width) { _, w in measuredW = w }
            })

            hoverReadout
        }
        .onAppear {
            reveal = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.1)) { reveal = true }
        }
    }

    private func laneLabel(_ agent: AgentKind) -> some View {
        let n = project.sessions.filter { $0.agent == agent }.count
        return HStack(spacing: 6) {
            Image(systemName: agent.symbol).font(.system(size: 10, weight: .bold))
                .foregroundStyle(agent.color)
            VStack(alignment: .leading, spacing: 0) {
                Text(agent.display).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.textStrong).lineLimit(1)
                Text("\(n) 会话").font(.system(size: 8.5)).foregroundStyle(theme.textDim)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(agent.color.opacity(0.12), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(agent.color.opacity(0.22), lineWidth: 0.5))
        .frame(width: labelW - 14, alignment: .leading)
    }

    @ViewBuilder
    private func capsuleView(_ p: Placed, lane: Lane, plotW: CGFloat) -> some View {
        let isHover = hovered == p.s.id
        let cx = labelW + p.x + p.w / 2
        let cy = lane.top + vpad + CGFloat(p.row) * rowStride + barH / 2
        let startFrac = (p.x / plotW)
        SessionCapsule(color: p.s.agent.color, width: reveal ? p.w : 4,
                       height: isHover ? barH + 4 : barH, hover: isHover)
            .position(x: reveal ? cx : labelW, y: cy)
            .opacity(reveal ? 1 : 0)
            .zIndex(isHover ? 2 : 1)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(startFrac * 0.2), value: reveal)
            .onHover { h in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    hovered = h ? p.s.id : (hovered == p.s.id ? nil : hovered)
                }
            }
            .onTapGesture { openSession(p.s) }
    }

    private var hoverReadout: some View {
        Group {
            if let id = hovered, let h = project.sessions.first(where: { $0.id == id }) {
                HStack(spacing: 8) {
                    AgentBadge(agent: h.agent, compact: true)
                    Text(h.title).font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme.textStrong).lineLimit(1)
                    Text("\(Fmt.day(h.startedAt)) · \(Fmt.duration(h.duration)) · \(h.messageCount) 消息")
                        .font(.system(size: 10.5)).foregroundStyle(theme.textDim)
                }
                .transition(.opacity)
            } else {
                Text("横轴为时间 · 泳道内的空隙即贡献中断 · 悬停查看，点击打开")
                    .font(.system(size: 10.5)).foregroundStyle(theme.textDim)
            }
        }
        .frame(height: 18)
    }
}

private struct SessionCapsule: View {
    var color: Color
    var width: CGFloat
    var height: CGFloat
    var hover: Bool

    var body: some View {
        Capsule(style: .continuous)
            .fill(LinearGradient(colors: [color, color.opacity(0.72)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: height)
            .overlay(
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.4), .clear],
                                         startPoint: .top, endPoint: .center))
                    .padding(0.5))
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(hover ? 0.7 : 0.22), lineWidth: 0.75))
            .shadow(color: color.opacity(hover ? 0.7 : 0.3), radius: hover ? 9 : 4, y: 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hover)
    }
}

// MARK: - Rhythm (hour-of-day × weekday)

struct RhythmBucket: Identifiable {
    var id: String { label }
    var label: String
    var order: Int
    var count: Int
}

struct RhythmView: View {
    var sessions: [SessionRecord]

    private var hourBuckets: [RhythmBucket] {
        var h = Array(repeating: 0, count: 24)
        let cal = Calendar.current
        for s in sessions { h[cal.component(.hour, from: s.startedAt)] += 1 }
        return (0..<24).map { RhythmBucket(label: "\($0)", order: $0, count: h[$0]) }
    }

    private var weekdayBuckets: [RhythmBucket] {
        var w = Array(repeating: 0, count: 7)
        let cal = Calendar.current
        for s in sessions { w[cal.component(.weekday, from: s.startedAt) - 1] += 1 }
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return (0..<7).map { RhythmBucket(label: names[$0], order: $0, count: w[$0]) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "开工时刻", subtitle: "会话按启动小时分布")
                    RhythmChart(buckets: hourBuckets, color: V.violet, xLabelEvery: 6, unit: "时")
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "星期节律", subtitle: "会话按星期分布")
                    RhythmChart(buckets: weekdayBuckets, color: V.teal, xLabelEvery: 1)
                }
            }
        }
    }
}

private struct RhythmChart: View {
    var buckets: [RhythmBucket]
    var color: Color
    var xLabelEvery: Int
    var unit: String = ""
    @State private var sel: String?

    private var selected: RhythmBucket? { buckets.first { $0.label == sel } }

    var body: some View {
        Chart(buckets) { (b: RhythmBucket) in
            BarMark(
                x: .value("桶", b.label),
                y: .value("会话", b.count),
                width: .ratio(0.6))
            .cornerRadius(3)
            .foregroundStyle(color.gradient)
            .opacity(sel == nil || sel == b.label ? 1 : 0.26)
        }
        .chartXScale(domain: buckets.map(\.label))
        .chartXSelection(value: $sel)
        .chartXAxis {
            AxisMarks { value in
                if value.index % xLabelEvery == 0 {
                    AxisValueLabel()
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 170)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: sel)
        .overlay(alignment: .top) {
            if let s = selected {
                HStack(spacing: 5) {
                    Text("\(s.label)\(unit)").font(.system(size: 10, weight: .semibold))
                    Text("\(s.count) 会话").font(.system(size: 10)).foregroundStyle(color)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: .capsule)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }
}

// MARK: - Empty state

struct EmptyHint: View {
    var symbol: String
    var text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(V.textDim)
            Text(text).font(.system(size: 12)).foregroundStyle(V.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
