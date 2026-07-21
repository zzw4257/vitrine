import SwiftUI

// MARK: - Design tokens

enum V {
    static let violet = Color(red: 0.49, green: 0.36, blue: 1.00)
    static let teal   = Color(red: 0.18, green: 0.83, blue: 0.75)
    static let coral  = Color(red: 0.96, green: 0.51, blue: 0.40)
    static let rose   = Color(red: 0.95, green: 0.45, blue: 0.60)
    static let amber  = Color(red: 1.00, green: 0.72, blue: 0.30)
    static let sky    = Color(red: 0.35, green: 0.65, blue: 1.00)
    static let indigo = Color(red: 0.42, green: 0.47, blue: 0.98)   // Cursor
    static let mint   = Color(red: 0.30, green: 0.80, blue: 0.62)   // Windsurf

    static let accent = LinearGradient(
        colors: [violet, teal],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let textDim = Color.primary.opacity(0.55)
    static let hairline = Color.primary.opacity(0.08)

    static let corner: CGFloat = 22
}

extension Font {
    static func vStat(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static var vMono: Font { .system(size: 12, weight: .regular, design: .monospaced) }
}

// MARK: - Aurora background

/// The backdrop. Rendered three ways depending on the theme's BackgroundMode:
/// aurora (drifting blobs) · wash (calm, soft, slow — Apple) · flat (solid canvas — GitHub).
struct AuroraBackground: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = theme.palette
        let baseGradient = LinearGradient(colors: palette.base, startPoint: .top, endPoint: .bottom)

        Group {
            switch palette.background {
            case .flat:
                // Flat engineered canvas — a whisper of gradient, no motion.
                baseGradient
            case .wash, .aurora:
                blobField(palette: palette, mode: palette.background)
                    .background(baseGradient)
            }
        }
        .overlay {
            if palette.pattern != .none {
                PatternOverlay(kind: palette.pattern, color: palette.accent1,
                               scheme: palette.scheme)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if palette.ambientMotes && !reduceMotion {
                MoteField(colors: palette.aurora, intensity: theme.auroraIntensity)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func drawBlobs(_ ctx: inout GraphicsContext, size: CGSize, palette: Palette, wash: Bool, alphaK: Double, blur: CGFloat, t: Double) {
        ctx.addFilter(.blur(radius: blur))
        func blob(_ phase: Double, _ color: Color, _ scale: CGFloat, _ alpha: CGFloat) {
            let drift = wash ? 0.30 : 0.42
            let x = size.width  * (0.5 + drift * CGFloat(cos(t * 0.9 + phase)))
            let y = size.height * (0.5 + drift * CGFloat(sin(t * 0.7 + phase * 1.7)))
            let r = min(size.width, size.height) * scale
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [color.opacity(alpha * alphaK), color.opacity(0)]),
                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
        }
        let c = palette.aurora
        let s: CGFloat = wash ? 0.62 : 0.55
        blob(0.0, c[0], s, 0.50)
        blob(2.1, c[1], s - 0.07, 0.36)
        blob(4.2, c[2], s - 0.13, 0.26)
        blob(5.6, c[3], s - 0.19, 0.20)
    }

    @ViewBuilder
    private func blobField(palette: Palette, mode: BackgroundMode) -> some View {
        let intensity = theme.auroraIntensity
        let wash = mode == .wash
        let speed = (0.5 + intensity) * palette.motionScale
        let alphaK = (wash ? 0.22 : 0.35) + intensity * (wash ? 0.4 : 0.75)
        let blur: CGFloat = wash ? 130 : 90

        if reduceMotion {
            // Static, pleasing composition — no looping background motion.
            Canvas { ctx, size in drawBlobs(&ctx, size: size, palette: palette, wash: wash, alphaK: alphaK, blur: blur, t: 1.6) }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate / 18 * speed
                Canvas { ctx, size in drawBlobs(&ctx, size: size, palette: palette, wash: wash, alphaK: alphaK, blur: blur, t: t) }
            }
        }
    }
}

/// Subtle static texture over the backdrop — dot grid / lines / contours — so large empty areas
/// read as designed surface rather than blank. Drawn once, very low opacity, theme-tinted.
struct PatternOverlay: View {
    var kind: PatternKind
    var color: Color
    var scheme: ColorScheme

    var body: some View {
        Canvas { ctx, size in
            let a = scheme == .dark ? 0.085 : 0.06
            let ink = color.opacity(a)
            let step: CGFloat = 26
            switch kind {
            case .none:
                break
            case .dots:
                var y: CGFloat = step / 2
                while y < size.height {
                    var x: CGFloat = step / 2
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)),
                                 with: .color(ink))
                        x += step
                    }
                    y += step
                }
            case .grid:
                var p = Path()
                var x: CGFloat = 0
                while x < size.width { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y < size.height { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)); y += step }
                ctx.stroke(p, with: .color(ink), lineWidth: 0.6)
            case .diagonal:
                var p = Path()
                let gap: CGFloat = 22
                var d: CGFloat = -size.height
                while d < size.width {
                    p.move(to: .init(x: d, y: 0)); p.addLine(to: .init(x: d + size.height, y: size.height)); d += gap
                }
                ctx.stroke(p, with: .color(ink), lineWidth: 0.7)
            case .plus:
                var y: CGFloat = step / 2
                while y < size.height {
                    var x: CGFloat = step / 2
                    while x < size.width {
                        var p = Path()
                        p.move(to: .init(x: x - 3, y: y)); p.addLine(to: .init(x: x + 3, y: y))
                        p.move(to: .init(x: x, y: y - 3)); p.addLine(to: .init(x: x, y: y + 3))
                        ctx.stroke(p, with: .color(ink), lineWidth: 0.8)
                        x += step
                    }
                    y += step
                }
            case .topo:
                // Concentric contour rings from two offset centers — organic depth-map feel.
                let centers = [CGPoint(x: size.width * 0.22, y: size.height * 0.28),
                               CGPoint(x: size.width * 0.78, y: size.height * 0.72)]
                for c in centers {
                    var r: CGFloat = 34
                    while r < max(size.width, size.height) {
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                   with: .color(ink), lineWidth: 0.7)
                        r += 40
                    }
                }
            }
        }
    }
}

/// A handful of soft glowing motes drifting slowly on their own — ambient life for expressive
/// themes. Deterministic (no RNG) so it stays resume-safe; gated by reduce-motion at the call site.
struct MoteField: View {
    var colors: [Color]
    var intensity: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.addFilter(.blur(radius: 8))
                for i in 0..<9 {
                    let f = Double(i)
                    let px = 0.5 + 0.46 * cos(t * (0.05 + f * 0.006) + f * 1.7)
                    let py = 0.5 + 0.46 * sin(t * (0.045 + f * 0.005) + f * 2.3)
                    let x = size.width * px, y = size.height * py
                    let r = 2.0 + (f.truncatingRemainder(dividingBy: 3)) * 1.6
                    let col = colors[i % colors.count].opacity(0.22 + 0.16 * intensity)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(col))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: - Glass primitives

struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    var corner: CGFloat? = nil    // nil → theme corner radius
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .vitrineGlass(tint: tint, corner: corner, tintStrength: tint == nil ? 1 : 1.4)
    }
}

struct GlassChip: View {
    var text: String
    var color: Color = .secondary
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let s = systemImage { Image(systemName: s).font(.system(size: 9, weight: .semibold)) }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .lineLimit(1)
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(color.opacity(0.13), in: .capsule)
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }
}

struct StatTile: View {
    @Environment(ThemeManager.self) private var theme
    var title: String
    var value: String
    var symbol: String
    var color: Color
    /// When provided, the number rolls up from zero on appear.
    var numericValue: Double? = nil
    var format: ((Double) -> String)? = nil
    @State private var iconBounce = 0

    var body: some View {
        GlassCard(tint: color, padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                        .symbolEffect(.bounce, value: iconBounce)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textDim)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                Group {
                    if let numericValue, let format {
                        CountingText(value: numericValue, format: format,
                                     font: theme.number(34), key: "stat-\(title)")
                    } else {
                        Text(value)
                            .font(theme.number(34))
                            .contentTransition(.numericText())
                    }
                }
                .tracking(theme.tracking(34))
                .foregroundStyle(theme.textStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)
            }
        }
        .pointerParallax()
        .onHover { if $0 { iconBounce += 1 } }
    }
}

struct SectionHeader: View {
    @Environment(ThemeManager.self) private var theme
    var title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var iconColor: Color? = nil
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 9) {
            if let icon {
                let c = iconColor ?? theme.accent1
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c)
                    .frame(width: 26, height: 26)
                    .background(c.opacity(0.14), in: .rect(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(c.opacity(0.22), lineWidth: 0.5))
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.display(15, .semibold))
                    .foregroundStyle(theme.textStrong)
                if let s = subtitle {
                    Text(s).font(.system(size: 11)).foregroundStyle(theme.textDim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.05)) { appeared = true } }
    }
}

/// Themed page/display title — theme font design, size-aware tracking, strong text color.
private struct ThemedDisplay: ViewModifier {
    @Environment(ThemeManager.self) private var theme
    var size: CGFloat
    func body(content: Content) -> some View {
        content
            .font(theme.display(size))
            .tracking(theme.tracking(size))
            .foregroundStyle(theme.textStrong)
    }
}

extension View {
    func themedDisplay(_ size: CGFloat = 24) -> some View { modifier(ThemedDisplay(size: size)) }
}

// MARK: - Interaction

private struct HoverLift: ViewModifier {
    var scale: CGFloat
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(_ scale: CGFloat = 1.015) -> some View { modifier(HoverLift(scale: scale)) }

    /// Cap content at a comfortable reading width and center it, so the UI stays composed
    /// on ultrawide / fullscreen instead of stretching edge-to-edge.
    func centeredContent(_ maxWidth: CGFloat = 1360) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity, alignment: .center)
    }

    /// Standard staggered appearance for card grids.
    func cardTransition() -> some View {
        transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity))
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000_000_000...: return String(format: "%.1fT", Double(n) / 1_000_000_000_000)
        case 1_000_000_000...:     return String(format: "%.1fB", Double(n) / 1_000_000_000)
        case 1_000_000...:         return String(format: "%.1fM", Double(n) / 1_000_000)
        case 10_000...:            return String(format: "%.0fk", Double(n) / 1_000)
        case 1_000...:             return String(format: "%.1fk", Double(n) / 1_000)
        default:                   return "\(n)"
        }
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day())
    }

    static func duration(_ t: TimeInterval) -> String {
        if t < 90 { return "\(Int(t))s" }
        if t < 5400 { return "\(Int(t / 60))m" }
        return String(format: "%.1fh", t / 3600)
    }
}
