import SwiftUI

// MARK: - Session display layouts

enum SessionLayout: String, CaseIterable, Identifiable {
    case list, masonry, grid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .list: "列表"
        case .masonry: "瀑布"
        case .grid: "方格"
        }
    }
    var icon: String {
        switch self {
        case .list: "list.bullet"
        case .masonry: "rectangle.3.offgrid"
        case .grid: "square.grid.2x2"
        }
    }
}

/// Renders a set of sessions in one of three forms — a compact list, a Pinterest-style masonry
/// of variable-height cards, or a uniform tile grid. List reuses the terse SessionRow; the other
/// two use the richer, agent-branded SessionCard.
struct SessionGallery: View {
    var sessions: [SessionRecord]
    var layout: SessionLayout

    var body: some View {
        switch layout {
        case .list:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                    SessionRow(session: s)
                        .appearStagger(i, trigger: layoutKey, baseDelay: 0.05, perItem: 0.03)
                }
            }
        case .grid:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                    SessionCard(session: s, compact: true)
                        .appearStagger(min(i, 20), trigger: layoutKey, baseDelay: 0.05, perItem: 0.03)
                }
            }
        case .masonry:
            MasonryFlow(sessions: sessions, layoutKey: layoutKey)
        }
    }

    // Re-trigger the entrance stagger whenever the layout or the session set changes.
    private var layoutKey: String { "\(layout.rawValue)-\(sessions.count)" }
}

// MARK: - Masonry (waterfall) — column-balanced by estimated card height

private struct MasonryFlow: View {
    var sessions: [SessionRecord]
    var layoutKey: String
    @State private var width: CGFloat = 0

    private var columnCount: Int { max(1, min(4, Int(width / 250))) }

    /// Greedy shortest-column packing using a cheap height estimate, so columns stay balanced
    /// and the layout reads as a true waterfall rather than fixed rows.
    private func columns() -> [[SessionRecord]] {
        let n = columnCount
        var cols = Array(repeating: [SessionRecord](), count: n)
        var heights = Array(repeating: 0.0, count: n)
        for s in sessions {
            let c = heights.firstIndex(of: heights.min() ?? 0) ?? 0
            cols[c].append(s)
            heights[c] += estimatedHeight(s)
        }
        return cols
    }

    private func estimatedHeight(_ s: SessionRecord) -> Double {
        let titleLines = min(3, Double(s.title.count) / 22.0 + 1)
        let snippet = SessionCard.snippet(for: s)
        let snippetLines = snippet.map { min(4.0, Double($0.count) / 32.0 + 1) } ?? 0
        return 96 + titleLines * 17 + snippetLines * 15
    }

    var body: some View {
        let cols = columns()
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<cols.count, id: \.self) { c in
                LazyVStack(spacing: 12) {
                    ForEach(Array(cols[c].enumerated()), id: \.element.id) { i, s in
                        SessionCard(session: s, showSnippet: true)
                            .appearStagger(min(i, 12), trigger: layoutKey, baseDelay: 0.05, perItem: 0.04)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { width = g.size.width }
                    .onChange(of: g.size.width) { _, w in width = w }
            }
        )
    }
}

// MARK: - Distinctive session card (agent-branded)

struct SessionCard: View {
    @Environment(\.openSession) private var openSession
    @Environment(ThemeManager.self) private var theme
    @Environment(AppStore.self) private var store
    var session: SessionRecord
    var compact: Bool = false
    var showSnippet: Bool = false
    @State private var hovering = false

    private var accent: Color { session.agent.color }

    /// The first user prompt that isn't just the title (falls back to a machine summary).
    static func snippet(for s: SessionRecord) -> String? {
        if let p = s.userPrompts.first(where: { $0 != s.title && $0.count > 12 }) { return p }
        return s.summary
    }

    private var modelLabel: String? {
        guard let raw = session.models.first else { return nil }
        let l = ModelInfo.label(raw)
        return l.isEmpty ? nil : l
    }

    var body: some View {
        Button { openSession(session) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: session.agent.symbol).font(.system(size: 10, weight: .bold))
                    Text(session.agent.display).font(.system(size: 10, weight: .semibold))
                    if session.isSubagent { GlassChip(text: "子", color: .gray) }
                    Spacer(minLength: 4)
                    Text(Fmt.relative(session.startedAt))
                        .font(.system(size: 9.5)).foregroundStyle(V.textDim)
                }
                .foregroundStyle(accent)

                Text(store.displayTitle(session))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textStrong)
                    .lineLimit(compact ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)

                if showSnippet, let sn = Self.snippet(for: session), sn != session.title {
                    Text(sn)
                        .font(.system(size: 11)).foregroundStyle(V.textDim)
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 2)

                HStack(spacing: 5) {
                    Image(systemName: "folder").font(.system(size: 8))
                    Text(session.projectName).lineLimit(1)
                }
                .font(.system(size: 10)).foregroundStyle(V.textDim)

                HStack(spacing: 9) {
                    metric("bubble.left.and.bubble.right", "\(session.messageCount)")
                    if session.totalTokens > 0 {
                        metric("bolt", Fmt.tokens(session.totalTokens))
                    }
                    Spacer(minLength: 0)
                    if let m = modelLabel {
                        Text(m).font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(ModelInfo.vendorColor(m))
                            .lineLimit(1)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: compact ? 118 : 0, alignment: .topLeading)
            .background {
                ZStack(alignment: .topTrailing) {
                    accent.opacity(hovering ? 0.12 : 0.06)
                    Image(systemName: session.agent.symbol)
                        .font(.system(size: 58, weight: .bold))
                        .foregroundStyle(accent.opacity(0.10))
                        .rotationEffect(.degrees(-8))
                        .offset(x: 14, y: -10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? accent.opacity(0.4) : theme.hairline, lineWidth: 1))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(accent)
                    .frame(width: 3).padding(.vertical, 11)
            }
            .contentShape(.rect)
        }
        .pressable(0.98)
        .hoverLift(1.02)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }

    private func metric(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8.5))
            Text(text).font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .foregroundStyle(V.textDim)
    }
}
