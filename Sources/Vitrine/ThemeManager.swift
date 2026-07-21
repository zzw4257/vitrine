import SwiftUI
import Observation

// MARK: - Palettes

/// How card/chrome surfaces are rendered — the biggest structural difference between themes.
enum SurfaceMode: String, Codable {
    case glass      // Vitrine liquid glass — heavy tinted blur
    case vibrancy   // Apple material — lighter blur + bright top edge + soft shadow
    case solid      // GitHub Primer — flat fill + crisp 1px border, no blur
}

/// What sits behind everything.
enum BackgroundMode: String, Codable {
    case aurora     // drifting radial blobs (Vitrine)
    case wash       // calm, slow, soft macOS-wallpaper-like vibrancy wash (Apple)
    case flat       // solid canvas, no motion (GitHub)
}

/// A subtle repeating texture drawn over the backdrop so the window doesn't read as flat/empty.
enum PatternKind: String, Codable {
    case none, dots, grid, diagonal, topo, plus
}

/// A named theme. Beyond color it carries structural tokens (surface material, background,
/// corner radius, edges) so themes are genuinely different designs, not recolors.
struct Palette: Identifiable, Hashable {
    var id: String
    var name: String
    var accent1: Color
    var accent2: Color
    var aurora: [Color]          // 4 drifting blob colors
    var base: [Color]            // 2-stop background gradient (top → bottom)
    var glassTint: Color         // tint mixed into glass surfaces

    // Structural design tokens
    var scheme: ColorScheme = .dark             // light/dark — flips overlays & controls
    var surface: SurfaceMode = .glass
    var background: BackgroundMode = .aurora
    var corner: CGFloat = 22
    var solidFill: Color = Color(white: 0.11)                    // card fill for .solid surfaces
    var solidBorder: Color = Color(white: 1.0, opacity: 0.09)    // border for .solid surfaces
    var edgeHighlight: Bool = false                              // bright top edge (Apple vibrancy)
    var motionScale: Double = 1.0                               // background motion multiplier
    var pattern: PatternKind = .none                            // subtle backdrop texture
    var ambientMotes: Bool = false                             // slow drifting glow motes for life

    // Typography & text tokens — the other half of a theme's identity.
    var fontDesign: Font.Design = .rounded      // Vitrine=rounded, Apple/GitHub=default
    var displayTracking: CGFloat = 0            // negative tightens large headings (Apple/GitHub)
    var monoNumbers: Bool = false               // GitHub renders stats in mono
    var textStrong: Color = .primary
    var textDim: Color = Color.white.opacity(0.55)
    var textFaint: Color = Color.white.opacity(0.38)
    /// Discrete intensity ramp for the heatmap (e.g. GitHub's contribution greens).
    /// nil → the heatmap fades the accent by opacity.
    var heatRamp: [Color]? = nil
    /// Emblem shown in the theme picker: apple / github / prism (default).
    var emblem: String = "prism"

    var accentGradient: LinearGradient {
        LinearGradient(colors: [accent1, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Palettes {
    static let nebula = Palette(
        id: "nebula", name: "星云",
        accent1: Color(red: 0.49, green: 0.36, blue: 1.00),
        accent2: Color(red: 0.18, green: 0.83, blue: 0.75),
        aurora: [Color(red: 0.49, green: 0.36, blue: 1.0), Color(red: 0.18, green: 0.83, blue: 0.75),
                 Color(red: 0.95, green: 0.45, blue: 0.60), Color(red: 0.35, green: 0.65, blue: 1.0)],
        base: [Color(red: 0.055, green: 0.05, blue: 0.11), Color(red: 0.02, green: 0.02, blue: 0.05)],
        glassTint: Color(red: 0.49, green: 0.36, blue: 1.0),
        pattern: .dots, ambientMotes: true)

    static let sunset = Palette(
        id: "sunset", name: "落日",
        accent1: Color(red: 1.00, green: 0.55, blue: 0.35),
        accent2: Color(red: 0.96, green: 0.30, blue: 0.52),
        aurora: [Color(red: 1.0, green: 0.55, blue: 0.35), Color(red: 0.96, green: 0.30, blue: 0.52),
                 Color(red: 1.0, green: 0.78, blue: 0.35), Color(red: 0.62, green: 0.24, blue: 0.55)],
        base: [Color(red: 0.10, green: 0.05, blue: 0.08), Color(red: 0.04, green: 0.02, blue: 0.04)],
        glassTint: Color(red: 1.0, green: 0.45, blue: 0.42),
        pattern: .diagonal, ambientMotes: true)

    static let ocean = Palette(
        id: "ocean", name: "深海",
        accent1: Color(red: 0.20, green: 0.70, blue: 1.00),
        accent2: Color(red: 0.20, green: 0.90, blue: 0.78),
        aurora: [Color(red: 0.20, green: 0.70, blue: 1.0), Color(red: 0.20, green: 0.90, blue: 0.78),
                 Color(red: 0.35, green: 0.45, blue: 0.95), Color(red: 0.30, green: 0.82, blue: 0.90)],
        base: [Color(red: 0.03, green: 0.06, blue: 0.12), Color(red: 0.01, green: 0.03, blue: 0.06)],
        glassTint: Color(red: 0.25, green: 0.75, blue: 1.0),
        pattern: .topo, ambientMotes: true)

    static let forest = Palette(
        id: "forest", name: "苔原",
        accent1: Color(red: 0.45, green: 0.85, blue: 0.55),
        accent2: Color(red: 0.60, green: 0.80, blue: 0.30),
        aurora: [Color(red: 0.45, green: 0.85, blue: 0.55), Color(red: 0.60, green: 0.80, blue: 0.30),
                 Color(red: 0.25, green: 0.70, blue: 0.60), Color(red: 0.80, green: 0.85, blue: 0.40)],
        base: [Color(red: 0.04, green: 0.08, blue: 0.06), Color(red: 0.02, green: 0.04, blue: 0.03)],
        glassTint: Color(red: 0.45, green: 0.82, blue: 0.52),
        pattern: .plus, ambientMotes: true)

    static let mono = Palette(
        id: "mono", name: "石墨",
        accent1: Color(red: 0.80, green: 0.82, blue: 0.88),
        accent2: Color(red: 0.55, green: 0.58, blue: 0.66),
        aurora: [Color(red: 0.55, green: 0.58, blue: 0.68), Color(red: 0.42, green: 0.45, blue: 0.55),
                 Color(red: 0.65, green: 0.68, blue: 0.78), Color(red: 0.35, green: 0.38, blue: 0.48)],
        base: [Color(red: 0.06, green: 0.065, blue: 0.08), Color(red: 0.02, green: 0.022, blue: 0.03)],
        glassTint: Color(red: 0.6, green: 0.63, blue: 0.72),
        pattern: .grid, ambientMotes: false)

    // MARK: Genuine platform themes (structural, not recolors)

    /// Apple — translucent vibrancy material, bright light-catching edges, a calm slow desktop
    /// wash behind frosted chrome, restrained corners, system blue. (apple-design §12, §15, §16)
    static let apple = Palette(
        id: "apple", name: "Apple 深色",
        accent1: Color(red: 0.04, green: 0.52, blue: 1.00),      // systemBlue (dark) #0A84FF
        accent2: Color(red: 0.35, green: 0.34, blue: 0.84),      // systemIndigo #5E5CE6
        // Soft, desaturated pastels — like a blurred macOS wallpaper, not neon.
        aurora: [Color(red: 0.36, green: 0.52, blue: 0.92), Color(red: 0.55, green: 0.45, blue: 0.85),
                 Color(red: 0.90, green: 0.55, blue: 0.70), Color(red: 0.45, green: 0.70, blue: 0.90)],
        base: [Color(red: 0.09, green: 0.10, blue: 0.13), Color(red: 0.04, green: 0.045, blue: 0.06)],
        glassTint: Color(red: 0.55, green: 0.60, blue: 0.78),
        surface: .vibrancy, background: .wash, corner: 15,
        edgeHighlight: true, motionScale: 0.35,
        // SF Pro feel: default (non-rounded) design, tighten large text, macOS label grays.
        fontDesign: .default, displayTracking: -0.6, monoNumbers: false,
        textStrong: Color(white: 0.96), textDim: Color(white: 0.62), textFaint: Color(white: 0.42),
        emblem: "apple")

    /// GitHub — Primer dark: flat canvas, solid cards with crisp hairline borders, small radius,
    /// no blur, no drifting light. Blue links + green primary. Reads engineered, not glassy.
    static let github = Palette(
        id: "github", name: "GitHub 深色",
        accent1: Color(red: 0.18, green: 0.51, blue: 0.97),      // accent.fg #2f81f7
        accent2: Color(red: 0.25, green: 0.72, blue: 0.31),      // success #3fb950
        aurora: [Color(red: 0.18, green: 0.51, blue: 0.97), Color(red: 0.25, green: 0.72, blue: 0.31),
                 Color(red: 0.18, green: 0.51, blue: 0.97), Color(red: 0.25, green: 0.72, blue: 0.31)],
        base: [Color(red: 0.051, green: 0.067, blue: 0.090), Color(red: 0.004, green: 0.016, blue: 0.035)], // #0d1117 → #010409
        glassTint: Color(red: 0.18, green: 0.51, blue: 0.97),
        surface: .solid, background: .flat, corner: 8,
        solidFill: Color(red: 0.086, green: 0.106, blue: 0.133),   // canvas.overlay #161b22
        solidBorder: Color(red: 0.188, green: 0.212, blue: 0.239), // border.default #30363d
        edgeHighlight: false, motionScale: 0,
        // Primer: functional default type, mono numerals, exact fg grays.
        fontDesign: .default, displayTracking: -0.3, monoNumbers: true,
        textStrong: Color(red: 0.902, green: 0.929, blue: 0.953),  // fg.default #e6edf3
        textDim: Color(red: 0.490, green: 0.522, blue: 0.565),     // fg.muted #7d8590
        textFaint: Color(red: 0.376, green: 0.408, blue: 0.447),   // #606a76
        // GitHub's exact contribution-graph greens (dark).
        heatRamp: [Color(red: 0.055, green: 0.267, blue: 0.161),   // #0e4429
                   Color(red: 0.0, green: 0.427, blue: 0.196),     // #006d32
                   Color(red: 0.149, green: 0.651, blue: 0.255),   // #26a641
                   Color(red: 0.224, green: 0.827, blue: 0.325)],  // #39d353
        emblem: "github")

    /// Apple light — macOS/iOS light: frosted white vibrancy on a calm light-gray wash, system blue.
    static let appleLight = Palette(
        id: "apple-light", name: "Apple 浅色",
        accent1: Color(red: 0.0, green: 0.478, blue: 1.0),        // systemBlue #007AFF
        accent2: Color(red: 0.345, green: 0.337, blue: 0.839),    // systemIndigo #5856D6
        aurora: [Color(red: 0.60, green: 0.72, blue: 0.98), Color(red: 0.74, green: 0.66, blue: 0.94),
                 Color(red: 0.98, green: 0.74, blue: 0.82), Color(red: 0.66, green: 0.82, blue: 0.96)],
        base: [Color(red: 0.949, green: 0.949, blue: 0.969), Color(red: 0.906, green: 0.906, blue: 0.929)], // #f2f2f7
        glassTint: Color(red: 0.55, green: 0.62, blue: 0.85),
        scheme: .light, surface: .vibrancy, background: .wash, corner: 15,
        edgeHighlight: true, motionScale: 0.3,
        fontDesign: .default, displayTracking: -0.6, monoNumbers: false,
        textStrong: Color(red: 0.11, green: 0.11, blue: 0.12),    // label #1d1d1f
        textDim: Color(red: 0.43, green: 0.43, blue: 0.45),       // secondaryLabel #6e6e73
        textFaint: Color(red: 0.60, green: 0.60, blue: 0.63),
        emblem: "apple")

    /// GitHub light — github.com default: white canvas, subtle gray cards, #d0d7de borders,
    /// blue #0969da + green #1a7f37, light contribution greens.
    static let githubLight = Palette(
        id: "github-light", name: "GitHub 浅色",
        accent1: Color(red: 0.035, green: 0.412, blue: 0.855),    // accent.fg #0969da
        accent2: Color(red: 0.102, green: 0.498, blue: 0.216),    // success #1a7f37
        aurora: [Color(red: 0.035, green: 0.412, blue: 0.855), Color(red: 0.102, green: 0.498, blue: 0.216),
                 Color(red: 0.035, green: 0.412, blue: 0.855), Color(red: 0.102, green: 0.498, blue: 0.216)],
        base: [Color(red: 1.0, green: 1.0, blue: 1.0), Color(red: 0.965, green: 0.973, blue: 0.980)],       // #ffffff → #f6f8fa
        glassTint: Color(red: 0.035, green: 0.412, blue: 0.855),
        scheme: .light, surface: .solid, background: .flat, corner: 8,
        solidFill: Color(red: 1.0, green: 1.0, blue: 1.0),        // white cards on the subtle canvas
        solidBorder: Color(red: 0.816, green: 0.843, blue: 0.871), // border.default #d0d7de
        edgeHighlight: false, motionScale: 0,
        fontDesign: .default, displayTracking: -0.3, monoNumbers: true,
        textStrong: Color(red: 0.122, green: 0.137, blue: 0.157), // fg.default #1f2328
        textDim: Color(red: 0.349, green: 0.388, blue: 0.431),    // fg.muted #59636e
        textFaint: Color(red: 0.51, green: 0.55, blue: 0.59),
        // GitHub's light contribution greens.
        heatRamp: [Color(red: 0.608, green: 0.914, blue: 0.659),  // #9be9a8
                   Color(red: 0.251, green: 0.769, blue: 0.388),  // #40c463
                   Color(red: 0.188, green: 0.631, blue: 0.306),  // #30a14e
                   Color(red: 0.129, green: 0.431, blue: 0.224)], // #216e39
        emblem: "github")

    static let all: [Palette] = [nebula, sunset, ocean, forest, mono, apple, appleLight, github, githubLight]
    static func by(_ id: String) -> Palette { all.first { $0.id == id } ?? nebula }
}

// MARK: - Theme manager

@Observable
final class ThemeManager {
    var paletteID: String { didSet { persist() } }
    /// 0 = the clearest glass (barely tinted), 1 = frosted/opaque.
    var glassOpacity: Double { didSet { persist() } }
    /// 0 = borderless, 1 = strong hairlines for maximum card separation.
    var borderStrength: Double { didSet { persist() } }
    /// 0 = calm/static aurora, 1 = vivid drifting aurora.
    var auroraIntensity: Double { didSet { persist() } }

    var palette: Palette { Palettes.by(paletteID) }

    var accentGradient: LinearGradient { palette.accentGradient }
    var accent1: Color { palette.accent1 }
    var accent2: Color { palette.accent2 }
    var corner: CGFloat { palette.corner }
    var surface: SurfaceMode { palette.surface }
    var scheme: ColorScheme { palette.scheme }

    // Text tokens
    var textStrong: Color { palette.textStrong }
    var textDim: Color { palette.textDim }
    var textFaint: Color { palette.textFaint }

    // Scheme-aware neutral overlays (work on both light and dark canvases).
    private var isLight: Bool { palette.scheme == .light }
    var hoverBg: Color { isLight ? .black.opacity(0.05) : .white.opacity(0.06) }
    var sidebarBg: Color { isLight ? .black.opacity(0.035) : .black.opacity(0.14) }
    var hairline: Color { isLight ? .black.opacity(0.10) : .white.opacity(0.08) }
    /// Recessed input-well fill (code editors, command boxes) — subtle on light, dark on dark.
    var well: Color { isLight ? .black.opacity(0.045) : .black.opacity(0.28) }

    /// Display / heading font in the theme's type design.
    func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: palette.fontDesign)
    }
    /// Numeric font — mono for GitHub, the theme design otherwise. Tracking applied by caller.
    func number(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: palette.monoNumbers ? .monospaced : palette.fontDesign)
    }
    /// Tracking for large text — tightens headings on Apple/GitHub, 0 on Vitrine.
    func tracking(_ size: CGFloat) -> CGFloat { size >= 22 ? palette.displayTracking : 0 }

    /// Border color for card separation, scaled by the knob.
    var borderColor: Color { .white.opacity(0.04 + borderStrength * 0.20) }
    var borderWidth: CGFloat { borderStrength < 0.02 ? 0 : 0.5 + borderStrength * 1.0 }

    /// Tint opacity mixed into a themed glass surface.
    func tintOpacity(_ base: Double = 1) -> Double { (0.04 + glassOpacity * 0.20) * base }

    /// Accent-tinted selection fill that adapts to the surface mode (glass vs solid).
    @ViewBuilder
    func selectionFill(_ shape: some InsettableShape, tint: Color? = nil) -> some View {
        let c = tint ?? palette.accent1
        switch palette.surface {
        case .solid:
            shape.fill(c.opacity(0.16))
                .overlay(shape.strokeBorder(c.opacity(0.5), lineWidth: 1))
        case .vibrancy:
            shape.fill(.white.opacity(0.001))
                .glassEffect(.regular.tint(c.opacity(0.16)), in: shape)
                .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.3), .clear],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1))
        case .glass:
            shape.fill(.white.opacity(0.001))
                .glassEffect(.regular.tint(c.opacity(0.10 + glassOpacity * 0.28)), in: shape)
        }
    }

    init() {
        let d = UserDefaults.standard
        paletteID = d.string(forKey: "vitrine.paletteID") ?? "nebula"
        glassOpacity = d.object(forKey: "vitrine.glassOpacity") as? Double ?? 0.45
        borderStrength = d.object(forKey: "vitrine.borderStrength") as? Double ?? 0.35
        auroraIntensity = d.object(forKey: "vitrine.auroraIntensity") as? Double ?? 0.75
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(paletteID, forKey: "vitrine.paletteID")
        d.set(glassOpacity, forKey: "vitrine.glassOpacity")
        d.set(borderStrength, forKey: "vitrine.borderStrength")
        d.set(auroraIntensity, forKey: "vitrine.auroraIntensity")
    }
}

// MARK: - Themed glass

/// A themed surface that renders differently per SurfaceMode:
/// glass (liquid glass) · vibrancy (Apple material + bright top edge + shadow) · solid (GitHub flat card).
private struct ThemedSurface<S: InsettableShape>: ViewModifier {
    @Environment(ThemeManager.self) private var theme
    var tint: Color?
    var shape: S
    var tintStrength: Double

    func body(content: Content) -> some View {
        let p = theme.palette
        let t = tint ?? p.glassTint
        switch p.surface {
        case .solid:
            content
                .background(shape.fill(p.solidFill))
                .overlay(shape.strokeBorder(
                    p.solidBorder.opacity(0.55 + theme.borderStrength * 0.5),
                    lineWidth: 1))
        case .vibrancy:
            content
                .glassEffect(.regular.tint(t.opacity(theme.tintOpacity(tintStrength) * 0.5)), in: shape)
                // Bright top edge + faint inner top highlight = light catching a real material.
                .overlay(shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .clear, .white.opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
                .overlay(alignment: .top) {
                    shape.fill(LinearGradient(colors: [.white.opacity(0.06), .clear],
                                              startPoint: .top, endPoint: .center))
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.30), radius: 18, y: 10)
        case .glass:
            content
                .glassEffect(.regular.tint(t.opacity(theme.tintOpacity(tintStrength))), in: shape)
                .overlay(shape.strokeBorder(theme.borderColor, lineWidth: theme.borderWidth))
        }
    }
}

extension View {
    /// Themed card surface. `corner` nil → uses the theme's corner radius; continuous (squircle) corners.
    func vitrineGlass(tint: Color? = nil, corner: CGFloat? = nil, tintStrength: Double = 1) -> some View {
        // Resolved lazily via a wrapper so we can read theme.corner from the environment.
        modifier(ResolvedRectSurface(tint: tint, corner: corner, tintStrength: tintStrength))
    }

    /// Themed capsule pill surface.
    func vitrineGlassCapsule(tint: Color? = nil, tintStrength: Double = 1) -> some View {
        modifier(ThemedSurface(tint: tint, shape: Capsule(), tintStrength: tintStrength))
    }
}

private struct ResolvedRectSurface: ViewModifier {
    @Environment(ThemeManager.self) private var theme
    var tint: Color?
    var corner: CGFloat?
    var tintStrength: Double
    func body(content: Content) -> some View {
        let r = corner ?? theme.corner
        content.modifier(ThemedSurface(
            tint: tint, shape: RoundedRectangle(cornerRadius: r, style: .continuous),
            tintStrength: tintStrength))
    }
}
