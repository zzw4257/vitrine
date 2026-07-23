import SwiftUI
import AppKit
import Observation

/// Debug aid: pin the window above other apps so headless screenshots aren't occluded.
/// Enabled only when VITRINE_FLOAT=1; no effect on normal launches.
struct WindowFloater: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        guard ProcessInfo.processInfo.environment["VITRINE_FLOAT"] == "1" else { return v }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let w = v.window {
                w.level = .floating
                w.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Shared navigation + presentation state. A singleton so the menu-bar Commands
/// (which live outside the view hierarchy) can drive the same state the RootView reads.
@Observable
final class UIState {
    static let shared = UIState()
    var section: Section = {
        if let raw = ProcessInfo.processInfo.environment["VITRINE_SECTION"],
           let s = Section(rawValue: raw) { return s }
        return .dashboard
    }()
    var showSettings = ProcessInfo.processInfo.environment["VITRINE_OPEN_SETTINGS"] == "1"
    var replayOnboarding = false

    func go(_ s: Section) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { section = s }
    }
}

@main
struct VitrineApp: App {
    @State private var store = AppStore()
    @State private var theme = ThemeManager()
    @State private var ui = UIState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(theme)
                .environment(ui)
                .frame(minWidth: 860, minHeight: 600)
                .preferredColorScheme(theme.scheme)
                .task { await store.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands { VitrineCommands(store: store) }
    }
}

// MARK: - Menu bar

struct VitrineCommands: Commands {
    var store: AppStore
    private let ui = UIState.shared
    @Bindable private var keys = KeybindingManager.shared

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            let b = keys.binding(.settings)
            Button("设置…") { ui.showSettings = true }
                .keyboardShortcut(b.keyEquivalent, modifiers: b.eventModifiers)
        }
        CommandMenu("视图") {
            ForEach(Section.allCases) { s in
                if let action = actionFor(s) {
                    let b = keys.binding(action)
                    Button(s.title) { ui.go(s) }
                        .keyboardShortcut(b.keyEquivalent, modifiers: b.eventModifiers)
                }
            }
            Divider()
            let r = keys.binding(.refresh)
            Button("重新扫描全部会话") { Task { await store.refresh() } }
                .keyboardShortcut(r.keyEquivalent, modifiers: r.eventModifiers)
        }
    }

    private func actionFor(_ s: Section) -> KeyAction? {
        KeyAction.allCases.first { $0.section == s }
    }
}

// MARK: - Navigation

enum Section: String, CaseIterable, Identifiable {
    case dashboard, projects, search, memory, distillery, dispatch, pinned
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "总览"
        case .projects: "项目"
        case .search: "检索"
        case .memory: "记忆工坊"
        case .distillery: "技能蒸馏"
        case .dispatch: "任务调配"
        case .pinned: "已置顶"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "circle.grid.cross"
        case .projects: "square.stack.3d.up"
        case .search: "magnifyingglass"
        case .memory: "brain"
        case .distillery: "flask"
        case .dispatch: "paperplane"
        case .pinned: "pin.fill"
        }
    }
}

/// Splash → (first run only) onboarding → the real app. Each phase is the ONLY thing in the view
/// tree while active — the sidebar/content aren't constructed during splash, so it reads as a
/// dedicated pre-app moment rather than a mask sitting on top of an already-built interface.
private enum LaunchPhase { case splash, onboarding, ready }

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @Environment(UIState.self) private var ui
    @State private var selectedSession: SessionRecord?
    @State private var userCollapsed = false
    @State private var phase: LaunchPhase = ProcessInfo.processInfo.environment["VITRINE_SECTION"] != nil
        ? .ready : .splash
    @Namespace private var sidebarNS

    private var forceOnboarding: Bool { ProcessInfo.processInfo.environment["VITRINE_ONBOARD"] == "1" }

    var body: some View {
        @Bindable var ui = ui
        Group {
            switch phase {
            case .splash:
                SplashView {
                    let goToOnboarding = !Onboarding.seen || forceOnboarding
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        phase = goToOnboarding ? .onboarding : .ready
                    }
                }
                .transition(.opacity)
            case .onboarding:
                OnboardingView(onDone: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .ready }
                })
                .environment(store)
                .environment(theme)
                .transition(.opacity)
            case .ready:
                mainInterface
                    .transition(.opacity)
            }
        }
        .onChange(of: ui.replayOnboarding) { if ui.replayOnboarding { phase = .onboarding; ui.replayOnboarding = false } }
    }

    private var mainInterface: some View {
        @Bindable var ui = ui
        return GeometryReader { geo in
            // Below ~940pt the sidebar auto-collapses to an icon rail; the user can also pin it.
            let collapsed = userCollapsed || geo.size.width < 940
            ZStack {
                AuroraBackground()
                HStack(spacing: 0) {
                    sidebar(collapsed: collapsed)
                        .frame(width: collapsed ? 78 : 212)
                    Divider().opacity(0.15)
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: collapsed)
            }
        }
        .sheet(item: $selectedSession) { s in
            SessionDetailView(session: s)
                .environment(store)
                .environment(theme)
        }
        .sheet(isPresented: $ui.showSettings) {
            SettingsView()
                .environment(store)
                .environment(theme)
                .environment(ui)
        }
        .environment(\.openSession, OpenSessionAction { selectedSession = $0 })
        .background(WindowFloater())
    }

    private var detail: some View {
        Group {
            switch ui.section {
            case .dashboard: DashboardView()
            case .projects: ProjectsView()
            case .search: SearchView()
            case .memory: MemoryStudioView()
            case .distillery: DistilleryView()
            case .dispatch: DispatchView()
            case .pinned: PinnedView()
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(x: 18)).combined(with: .scale(scale: 0.98, anchor: .topLeading)),
            removal: .opacity.combined(with: .offset(x: -12))))
        .id(ui.section)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: ui.section)
    }

    private func sidebar(collapsed: Bool) -> some View {
        VStack(alignment: collapsed ? .center : .leading, spacing: collapsed ? 6 : 4) {
            // Brand + (expanded) settings
            HStack(spacing: 10) {
                PrismMark(animate: true)
                    .frame(width: collapsed ? 22 : 19, height: collapsed ? 22 : 19)
                    .shadow(color: theme.accent1.opacity(0.4), radius: collapsed ? 5 : 0)
                    .frame(maxWidth: collapsed ? .infinity : nil)
                if !collapsed {
                    Text("Vitrine")
                        .font(theme.display(17, .bold))
                        .foregroundStyle(theme.textStrong)
                    Spacer()
                    SidebarIconButton(symbol: "slider.horizontal.3", help: "设置（⌘,）") { ui.showSettings = true }
                        .padding(.trailing, 12)
                }
            }
            .padding(.top, 42)
            .padding(.leading, collapsed ? 0 : 18)
            .padding(.bottom, collapsed ? 10 : 14)

            ForEach(Section.allCases) { s in
                SidebarItem(section: s, selected: ui.section == s, collapsed: collapsed, ns: sidebarNS) {
                    ui.go(s)
                }
            }

            Spacer()

            // Bottom controls
            if collapsed {
                VStack(spacing: 6) {
                    SidebarIconButton(symbol: "slider.horizontal.3", help: "设置（⌘,）", tile: true) { ui.showSettings = true }
                    SidebarIconButton(symbol: store.scanning ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
                                      help: store.status, tile: true, spinning: store.scanning) {
                        Task { await store.refresh() }
                    }
                    Divider().opacity(0.12).padding(.horizontal, 12)
                    SidebarIconButton(symbol: "sidebar.left", help: "展开边栏", tile: true) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { userCollapsed.toggle() }
                    }
                }
                .padding(.bottom, 4)
            } else {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { userCollapsed.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sidebar.leading").font(.system(size: 12, weight: .semibold))
                        Text("收起边栏").font(.system(size: 11.5, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(theme.textDim)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                scanFooter(collapsed: false)
            }
        }
        .padding(.horizontal, collapsed ? 12 : 10)
        .padding(.bottom, 12)
        .background(theme.sidebarBg)
    }

    private func scanFooter(collapsed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if collapsed {
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.scanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .help(store.status)
            } else if store.scanning {
                ProgressView(value: store.progress)
                    .progressViewStyle(.linear)
                    .tint(theme.accent2)
                Text(store.status)
                    .font(.system(size: 10))
                    .foregroundStyle(V.textDim)
                    .lineLimit(2)
            } else {
                HStack {
                    Text(store.status)
                        .font(.system(size: 10))
                        .foregroundStyle(V.textDim)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.vitrine)
                    .help("重新扫描全部会话")
                }
            }
        }
        .padding(collapsed ? 8 : 10)
        .vitrineGlass(corner: 14)
    }
}

private struct SidebarItem: View {
    @Environment(ThemeManager.self) private var theme
    let section: Section
    let selected: Bool
    var collapsed: Bool = false
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    private var shortcut: String? {
        KeyAction.allCases.first { $0.section == section }
            .map { KeybindingManager.shared.binding($0).display }
    }

    var body: some View {
        Button(action: action) {
            if collapsed { collapsedTile } else { expandedRow }
        }
        .pressable(0.96)
        .help(collapsed ? "\(section.title)   \(shortcut ?? "")" : "")
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }

    // Collapsed: a substantial centered icon tile (a real dock, not a cramped rail).
    private var collapsedTile: some View {
        Image(systemName: section.symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(selected ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.textDim))
            .symbolEffect(.bounce, value: selected)
            .frame(width: 48, height: 42)
            .background {
                if selected {
                    theme.selectionFill(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .matchedGeometryEffect(id: "sidebar-pill", in: ns)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.hoverBg)
                }
            }
            .scaleEffect(hovering && !selected ? 1.06 : 1)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
    }

    private var expandedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: section.symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(selected ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.textDim))
                .symbolEffect(.bounce, value: selected)
                .scaleEffect(selected ? 1.12 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: selected)
            Text(section.title)
                .font(theme.display(13, selected ? .semibold : .medium))
                .foregroundStyle(selected ? theme.textStrong : theme.textDim)
            Spacer()
            if let sc = shortcut {
                Text(sc)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(selected || hovering ? theme.textDim : theme.textFaint)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(theme.hoverBg.opacity(selected || hovering ? 1 : 0), in: .rect(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(.rect)
        .background {
            if selected {
                theme.selectionFill(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .matchedGeometryEffect(id: "sidebar-pill", in: ns)
            } else if hovering {
                RoundedRectangle(cornerRadius: 12).fill(theme.hoverBg)
            }
        }
    }
}

/// A round icon button for the sidebar chrome (settings/refresh/expand). Optional tile bg + spin.
private struct SidebarIconButton: View {
    @Environment(ThemeManager.self) private var theme
    var symbol: String
    var help: String
    var tile: Bool = false
    var spinning: Bool = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: tile ? 15 : 12, weight: .semibold))
                .foregroundStyle(theme.textDim)
                .symbolEffect(.rotate, isActive: spinning)
                .frame(width: tile ? 48 : 22, height: tile ? 42 : 22)
                .background {
                    if tile && hovering {
                        RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.hoverBg)
                    }
                }
                .scaleEffect(hovering ? 1.06 : 1)
                .contentShape(.rect)
        }
        .pressable()
        .help(help)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

// MARK: - Cross-view "open session" action

struct OpenSessionAction {
    var open: (SessionRecord) -> Void
    func callAsFunction(_ s: SessionRecord) { open(s) }
}

private struct OpenSessionKey: EnvironmentKey {
    static let defaultValue = OpenSessionAction { _ in }
}

extension EnvironmentValues {
    var openSession: OpenSessionAction {
        get { self[OpenSessionKey.self] }
        set { self[OpenSessionKey.self] = newValue }
    }
}
