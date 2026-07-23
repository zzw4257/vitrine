import SwiftUI

// MARK: - Shared brand mark (splash, onboarding, sidebar all draw the same glyph)

/// An animated glass prism that draws its edges and refracts a spectrum beam — Vitrine's one
/// recurring brand mark, so the splash, the onboarding ceremony, and the sidebar all read as the
/// same identity instead of three unrelated logos.
struct PrismMark: View {
    @Environment(ThemeManager.self) private var theme
    var animate: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let cx = size.width / 2, cy = size.height / 2
                let s = size.width * 0.34
                let top = CGPoint(x: cx, y: cy - s)
                let left = CGPoint(x: cx - s * 0.92, y: cy + s * 0.72)
                let right = CGPoint(x: cx + s * 0.92, y: cy + s * 0.72)
                var tri = Path()
                tri.move(to: top); tri.addLine(to: left); tri.addLine(to: right); tri.closeSubpath()

                // Refracted spectrum beam, gently pulsing
                let pulse = 0.5 + 0.5 * sin(t * 1.6)
                var beam = Path()
                beam.move(to: CGPoint(x: cx + s * 0.2, y: cy + s * 0.1))
                beam.addLine(to: CGPoint(x: cx + s * 1.5, y: cy + s * 0.7))
                beam.addLine(to: CGPoint(x: cx + s * 1.5, y: cy - s * 0.2))
                beam.closeSubpath()
                ctx.drawLayer { l in
                    l.clip(to: beam)
                    l.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                           with: .linearGradient(
                            Gradient(colors: [theme.accent1.opacity(0.15 + 0.35 * pulse),
                                              theme.accent2.opacity(0.1 + 0.3 * pulse)]),
                            startPoint: CGPoint(x: cx, y: cy), endPoint: CGPoint(x: size.width, y: cy)))
                }

                // Glass fill
                ctx.fill(tri, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.28), .white.opacity(0.05)]),
                    startPoint: top, endPoint: left))
                // Bright edges
                ctx.stroke(tri, with: .linearGradient(
                    Gradient(colors: [theme.accent1, theme.accent2]),
                    startPoint: top, endPoint: right),
                    style: StrokeStyle(lineWidth: 2.4, lineJoin: .round))
            }
        }
        .rotationEffect(.degrees(animate ? 0 : -20))
        .scaleEffect(animate ? 1 : 0.6)
        .animation(.spring(response: 0.8, dampingFraction: 0.6), value: animate)
    }
}

// MARK: - Launch splash

/// A dedicated pre-app brand beat. RootView shows ONLY this — the sidebar/content aren't built
/// yet, unlike the old approach of overlaying OnboardingView on top of an already-mounted
/// interface — so it reads as its own moment rather than a mask over the real app. Plays briefly
/// on every launch (a few hundred ms once resolved), while the scan already runs underneath;
/// the first-run tour (OnboardingView) is a separate step that follows it, only on first launch.
struct SplashView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onFinished: () -> Void

    @State private var shardsArrived = false
    @State private var resolved = false
    @State private var wordmarkIn = false
    @State private var exiting = false

    private let shardCount = 8

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 20) {
                ZStack {
                    if !reduceMotion {
                        ForEach(0..<shardCount, id: \.self) { i in
                            Shard(index: i, count: shardCount, arrived: shardsArrived)
                        }
                        .opacity(resolved ? 0 : 1)
                    }
                    PrismMark(animate: resolved || reduceMotion)
                        .frame(width: 104, height: 104)
                        .opacity(resolved || reduceMotion ? 1 : 0)
                }
                .frame(width: 168, height: 168)

                VStack(spacing: 5) {
                    Text("VITRINE")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .tracking(wordmarkIn ? 6 : 15)
                        .foregroundStyle(theme.accentGradient)
                    Text("一个玻璃质感的 Agent 指挥中心")
                        .font(.system(size: 11.5))
                        .foregroundStyle(V.textDim)
                }
                .opacity(wordmarkIn ? 1 : 0)
                .offset(y: wordmarkIn ? 0 : 8)
            }
            .opacity(exiting ? 0 : 1)
            .scaleEffect(exiting ? 1.05 : 1)
            .blur(radius: exiting ? 8 : 0)
        }
        .onAppear(perform: runSequence)
    }

    private func runSequence() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { resolved = true; wordmarkIn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { finish() }
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { shardsArrived = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { resolved = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.68) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { wordmarkIn = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) { finish() }
    }

    private func finish() {
        withAnimation(.easeIn(duration: 0.3)) { exiting = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { onFinished() }
    }
}

/// One converging light shard in the splash's assembly animation — a thin bright sliver that
/// flies in from a ring around the center and collapses into the prism forming at its core.
private struct Shard: View {
    @Environment(ThemeManager.self) private var theme
    var index: Int
    var count: Int
    var arrived: Bool

    private var angleDegrees: Double { (360.0 / Double(count)) * Double(index) }

    var body: some View {
        let startRadius: CGFloat = 128
        let rad = angleDegrees * .pi / 180
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [theme.accent1, theme.accent2],
                                  startPoint: .leading, endPoint: .trailing))
            .frame(width: arrived ? 3 : 24, height: 3)
            .rotationEffect(.degrees(angleDegrees))
            .offset(x: arrived ? 0 : cos(rad) * startRadius, y: arrived ? 0 : sin(rad) * startRadius)
            .animation(.spring(response: 0.55, dampingFraction: 0.7).delay(Double(index) * 0.018), value: arrived)
    }
}
