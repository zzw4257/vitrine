import SwiftUI

// MARK: - Themed button style

/// A button whose whole treatment follows the theme's surface language:
/// GitHub → flat Primer buttons (solid fill + hairline border), Apple → tinted/filled,
/// Vitrine → liquid glass. Replaces the system `.glass` / `.glassProminent` styles so buttons
/// stop looking glassy under the flat/vibrancy themes.
struct VitrineButton: ButtonStyle {
    @Environment(ThemeManager.self) private var theme
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let p = theme.palette
        let shape = RoundedRectangle(cornerRadius: max(6, p.corner * 0.45), style: .continuous)
        return configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(foreground(p))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background { background(p, shape) }
            .overlay { border(p, shape) }
            .contentShape(shape)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }

    private func foreground(_ p: Palette) -> Color {
        prominent ? .white : p.textStrong
    }

    @ViewBuilder private func background(_ p: Palette, _ shape: some Shape) -> some View {
        let light = p.scheme == .light
        switch p.surface {
        case .solid:
            if prominent {
                // GitHub primary green — #1f883d (light) / #238636 (dark)
                shape.fill(light ? Color(red: 0.122, green: 0.533, blue: 0.239)
                                 : Color(red: 0.137, green: 0.525, blue: 0.212))
            } else {
                // btn.bg — #f6f8fa (light) / #21262d (dark)
                shape.fill(light ? Color(red: 0.965, green: 0.973, blue: 0.980)
                                 : Color(red: 0.129, green: 0.149, blue: 0.176))
            }
        case .vibrancy:
            if prominent {
                shape.fill(p.accent1)
            } else {
                shape.fill(.white.opacity(0.10)).background(.ultraThinMaterial, in: shape)
            }
        case .glass:
            if prominent {
                shape.fill(.clear).glassEffect(.regular.tint(p.accent1.opacity(0.5)), in: shape)
            } else {
                shape.fill(.clear).glassEffect(.regular, in: shape)
            }
        }
    }

    @ViewBuilder private func border(_ p: Palette, _ shape: some InsettableShape) -> some View {
        switch p.surface {
        case .solid:
            shape.strokeBorder(prominent ? Color(red: 0.18, green: 0.60, blue: 0.28)
                                         : p.solidBorder, lineWidth: 1)
        case .vibrancy:
            shape.strokeBorder(.white.opacity(prominent ? 0.0 : 0.14), lineWidth: 1)
        case .glass:
            EmptyView()
        }
    }
}

extension ButtonStyle where Self == VitrineButton {
    static var vitrine: VitrineButton { VitrineButton(prominent: false) }
    static var vitrineProminent: VitrineButton { VitrineButton(prominent: true) }
}

// MARK: - Themed text field

/// A consistent, theme-aware container for text inputs: themed surface + a focus accent ring.
private struct VitrineField: ViewModifier {
    @Environment(ThemeManager.self) private var theme
    var focused: Bool
    var corner: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 9)
            .vitrineGlass(corner: corner, tintStrength: 0.3)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(theme.accent1.opacity(focused ? 0.85 : 0), lineWidth: 1.5))
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

extension View {
    func vitrineField(focused: Bool = false, corner: CGFloat = 11) -> some View {
        modifier(VitrineField(focused: focused, corner: corner))
    }

    /// Dismiss a sheet on Escape (SwiftUI sheets don't do this by default).
    func escapeToDismiss(_ dismiss: DismissAction) -> some View {
        background {
            Button("") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0).frame(width: 0, height: 0)
        }
    }
}

// MARK: - Distinctive theme preview swatch

/// The picker preview. Each theme renders in *its own* surface language and shows a signature
/// emblem — Apple mark, a GitHub contribution grid, or the palette's aurora dots.
struct ThemeSwatch: View {
    var palette: Palette
    var selected: Bool

    var body: some View {
        let r: CGFloat = 12
        VStack(spacing: 6) {
            ZStack {
                surface
                emblem
            }
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(palette.accentGradient)
                                           : AnyShapeStyle(Color.primary.opacity(0.14)),
                                  lineWidth: selected ? 2.5 : 1))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
            Text(palette.name)
                .font(.system(size: 10.5, weight: selected ? .semibold : .regular,
                              design: palette.fontDesign))
                .foregroundStyle(selected ? .primary : V.textDim)
        }
        .hoverLift(1.03)
    }

    // Background rendered in the theme's actual style so you preview the material, not just color.
    @ViewBuilder private var surface: some View {
        let base = LinearGradient(colors: palette.base, startPoint: .top, endPoint: .bottom)
        switch palette.background {
        case .flat:
            // GitHub: flat canvas + a solid bordered mini card, to telegraph "solid + hairline".
            ZStack {
                Rectangle().fill(palette.base[0])
                RoundedRectangle(cornerRadius: 5)
                    .fill(palette.solidFill)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(palette.solidBorder, lineWidth: 1))
                    .padding(8)
            }
        case .wash:
            // Apple: soft wash + a frosted vibrancy chip with a bright top edge.
            ZStack {
                base
                softBlobs(0.5)
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                        LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1))
                    .padding(9)
            }
        case .aurora:
            ZStack { base; softBlobs(0.85) }
        }
    }

    @ViewBuilder private var emblem: some View {
        switch palette.emblem {
        case "apple":
            Image(systemName: "apple.logo")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.3), radius: 3)
        case "github":
            ContribGrid(greens: palette.heatRamp ?? [palette.accent2])
        default:
            HStack(spacing: 4) {
                ForEach(palette.aurora.prefix(3).indices, id: \.self) { i in
                    Circle().fill(palette.aurora[i]).frame(width: 11, height: 11)
                        .shadow(color: palette.aurora[i].opacity(0.6), radius: 3)
                }
            }
        }
    }

    private func softBlobs(_ k: Double) -> some View {
        ZStack {
            ForEach(palette.aurora.prefix(3).indices, id: \.self) { i in
                Circle().fill(palette.aurora[i].opacity(0.5 * k))
                    .frame(width: 40, height: 40)
                    .blur(radius: 14)
                    .offset(x: CGFloat(i - 1) * 26, y: CGFloat((i % 2) * 2 - 1) * 8)
            }
        }
    }
}

/// A tiny GitHub-style contribution grid used as the GitHub theme emblem.
private struct ContribGrid: View {
    var greens: [Color]
    // Deterministic intensities (no RNG) that read like a real contribution graph.
    private let pattern: [[Int]] = [
        [0, 1, 2, 1, 3, 2, 1],
        [1, 2, 3, 2, 1, 3, 2],
        [0, 1, 1, 3, 2, 1, 0],
    ]
    var body: some View {
        VStack(spacing: 2.5) {
            ForEach(pattern.indices, id: \.self) { row in
                HStack(spacing: 2.5) {
                    ForEach(pattern[row].indices, id: \.self) { col in
                        let v = pattern[row][col]
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(v == 0 ? Color.white.opacity(0.06) : greens[min(v - 1, greens.count - 1)])
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
    }
}
