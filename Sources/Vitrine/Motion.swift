import SwiftUI

// MARK: - Staggered entrance

/// Cascade a view in (fade + rise + slight scale) with a per-index delay, so grids and
/// lists assemble themselves instead of snapping in flat. Re-fires when `trigger` changes.
private struct AppearStagger: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var index: Int
    var trigger: AnyHashable
    var baseDelay: Double
    var perItem: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            // Reduced motion: a plain cross-fade, no travel/scale/blur (apple-design §14).
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.96)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .blur(radius: shown || reduceMotion ? 0 : 3)
            .onAppear { fire() }
            .onChange(of: trigger) { shown = false; fire() }
    }

    private func fire() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25).delay(min(0.3, baseDelay + Double(index) * 0.02))) { shown = true }
            return
        }
        let delay = baseDelay + Double(index) * perItem
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(delay)) { shown = true }
    }
}

extension View {
    /// `index` orders the cascade; `trigger` replays it (e.g. the section id or a data-count).
    func appearStagger(_ index: Int, trigger: AnyHashable = 0,
                       baseDelay: Double = 0.02, perItem: Double = 0.05) -> some View {
        modifier(AppearStagger(index: index, trigger: trigger, baseDelay: baseDelay, perItem: perItem))
    }
}

// MARK: - Count-up number

/// Tracks which counters have already rolled up this session, so re-visiting a view shows
/// the final value immediately instead of replaying the count every time (which reads as busy).
@MainActor private var countedUpKeys = Set<String>()

/// A number that rolls up from zero to its value on first appearance (and animates on change).
struct CountingText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var value: Double
    var format: (Double) -> String
    var font: Font
    /// Stable identity so the roll-up plays once per session; nil = always roll up on appear.
    var key: String? = nil
    @State private var current: Double = 0

    var body: some View {
        Text(format(current))
            .font(font)
            .monospacedDigit()
            .onAppear {
                if reduceMotion || (key.map { countedUpKeys.contains($0) } ?? false) {
                    current = value
                    return
                }
                key.map { countedUpKeys.insert($0) }
                current = 0
                withAnimation(.spring(response: 0.9, dampingFraction: 0.9)) { current = value }
            }
            .onChange(of: value) { _, new in
                if reduceMotion { current = new }
                else { withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { current = new } }
            }
    }
}

// MARK: - Pointer parallax (subtle 3D tilt toward cursor)

private struct PointerParallax: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var maxAngle: Double
    @State private var size: CGSize = .zero
    @State private var dx: Double = 0   // -1...1
    @State private var dy: Double = 0
    @State private var active = false

    func body(content: Content) -> some View {
        if reduceMotion { return AnyView(content) }
        return AnyView(content
            .rotation3DEffect(.degrees(active ? -dy * maxAngle : 0),
                              axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(active ? dx * maxAngle : 0),
                              axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(active ? 1.012 : 1)
            .shadow(color: .black.opacity(active ? 0.22 : 0), radius: active ? 16 : 0, y: active ? 8 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: active)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: dx)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: dy)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { size = g.size }
                    .onChange(of: g.size) { _, s in size = s }
            })
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    active = true
                    guard size.width > 0, size.height > 0 else { return }
                    dx = Double((p.x / size.width) * 2 - 1).clamped(-1, 1)
                    dy = Double((p.y / size.height) * 2 - 1).clamped(-1, 1)
                case .ended:
                    active = false; dx = 0; dy = 0
                }
            })
    }
}

extension View {
    /// Subtle cursor-tracking tilt. Keep the angle small (3–5°) so it reads as depth, not a toy.
    func pointerParallax(maxAngle: Double = 4) -> some View {
        modifier(PointerParallax(maxAngle: maxAngle))
    }
}

private extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

// MARK: - Press feedback

private struct PressScale: ButtonStyle {
    var scale: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

extension View {
    /// Springy press-down feedback for tappable non-Button views.
    func pressable(_ scale: CGFloat = 0.95) -> some View {
        buttonStyle(PressScale(scale: scale))
    }
    /// A light band that sweeps across the content while `active` — signals "being generated".
    func shimmering(_ active: Bool) -> some View { modifier(Shimmer(active: active)) }
}

// MARK: - Shimmer (content being generated, e.g. an AI title in flight)

private struct Shimmer: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                GeometryReader { geo in
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                        let period = 1.5
                        let p = (tl.date.timeIntervalSinceReferenceDate
                                    .truncatingRemainder(dividingBy: period)) / period
                        let w = max(1, geo.size.width)
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: w * 0.45)
                            .offset(x: -w * 0.45 + (w * 1.45) * p)
                    }
                }
                .blendMode(.plusLighter)
                .mask(content)
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

// MARK: - Live pulse (for "running" / scanning indicators)

struct LivePulse: View {
    var color: Color
    var size: CGFloat = 8
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let p = 0.5 + 0.5 * sin(t * 2.4)
            ZStack {
                Circle().fill(color.opacity(0.35 * (1 - p))).frame(width: size + CGFloat(p) * 10, height: size + CGFloat(p) * 10)
                Circle().fill(color).frame(width: size, height: size)
            }
        }
    }
}
