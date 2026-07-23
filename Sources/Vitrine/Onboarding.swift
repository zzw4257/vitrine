import SwiftUI

// MARK: - Gate

enum Onboarding {
    private static let key = "vitrine.onboarded.v1"
    static var seen: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - The ceremonial first-run overlay

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    var onDone: () -> Void

    @State private var step = Int(ProcessInfo.processInfo.environment["VITRINE_ONBOARD_STEP"] ?? "") ?? 0
    @State private var appeared = false
    private let lastStep = 4

    var body: some View {
        ZStack {
            // Its own aurora, brightened, so the intro feels like a stage.
            AuroraBackground()
            Rectangle().fill(.black.opacity(0.25)).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .frame(maxWidth: 560)
                    .padding(40)
                    .background {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.black.opacity(0.28))
                            .vitrineGlass(corner: 28)
                    }
                    .scaleEffect(appeared ? 1 : 0.92)
                    .opacity(appeared ? 1 : 0)
                Spacer(minLength: 0)
                footer.padding(.bottom, 30)
            }
            .padding(40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { appeared = true }
        }
    }

    // MARK: content per step

    @ViewBuilder private var content: some View {
        VStack(spacing: 22) {
            PrismMark(animate: appeared)
                .frame(width: 96, height: 96)

            Group {
                switch step {
                case 0: welcome
                case 1: scanStep
                case 2: themeStep
                case 3: aiStep
                default: doneStep
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 14)),
                removal: .opacity.combined(with: .offset(y: -10))))
            .id(step)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Text("Vitrine")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(theme.accentGradient)
            Text("你的全 Agent / CLI 工作台")
                .font(.system(size: 15, weight: .medium))
            Text("把散落在 Claude Code、Codex、opencode 里的成百上千个会话，\n聚合成一个可检索、可视化、可调配的统一指挥中心。")
                .font(.system(size: 12.5))
                .foregroundStyle(V.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var scanStep: some View {
        VStack(spacing: 14) {
            Text("正在读取你的足迹").font(.system(size: 20, weight: .bold, design: .rounded))
            Text(store.scanning ? store.status : "扫描完成")
                .font(.system(size: 12)).foregroundStyle(V.textDim)
            HStack(spacing: 12) {
                OnbStat(value: "\(store.projects.count)", label: "项目", color: V.violet,
                        numeric: Double(store.projects.count))
                OnbStat(value: "\(store.sessions.count)", label: "会话", color: V.teal,
                        numeric: Double(store.sessions.count))
                OnbStat(value: Fmt.tokens(store.sessions.totalTokens), label: "总吞吐", color: V.amber)
                OnbStat(value: "\(store.sessions.dailyActivity().count)", label: "活跃天", color: V.rose,
                        numeric: Double(store.sessions.dailyActivity().count))
            }
            if store.scanning {
                ProgressView(value: store.progress).tint(theme.accent2).frame(maxWidth: 280)
            }
        }
    }

    private var themeStep: some View {
        VStack(spacing: 14) {
            Text("选一个你的主题").font(.system(size: 20, weight: .bold, design: .rounded))
            Text("含 Apple、GitHub 等风格 — 不只是换色，材质与背景都不同")
                .font(.system(size: 12)).foregroundStyle(V.textDim)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                ForEach(Palettes.all) { p in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { theme.paletteID = p.id }
                    } label: {
                        ThemeSwatch(palette: p, selected: theme.paletteID == p.id)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(theme.paletteID == p.id ? 1.05 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: theme.paletteID)
                }
            }
        }
    }

    private var aiStep: some View {
        VStack(spacing: 14) {
            Text("接入 AI（可选）").font(.system(size: 20, weight: .bold, design: .rounded))
            Text("用于会话总结、项目洞察、技能蒸馏。也可以之后再配。")
                .font(.system(size: 12)).foregroundStyle(V.textDim).multilineTextAlignment(.center)
            VStack(spacing: 8) {
                OnbAIRow(icon: "terminal", title: "本地 Claude CLI",
                         detail: store.claudePath != nil ? "已检测到，开箱即用" : "未检测到 claude",
                         ok: store.claudePath != nil, tint: V.coral) {
                    store.ai.applyProvider(AIProviders.localClaude)
                }
                OnbAIRow(icon: "cpu", title: "Ollama 本地推理",
                         detail: "本地 llama.cpp · 支持模型拉取",
                         ok: nil, tint: V.teal) {
                    store.ai.applyProvider(AIProviders.by("ollama"))
                }
                OnbAIRow(icon: "cloud", title: "云端 API",
                         detail: "OpenAI / DeepSeek / Kimi 等，去设置里填 Key",
                         ok: nil, tint: V.sky) {
                    store.ai.applyProvider(AIProviders.by("openai"))
                }
            }
            Text("当前：\(store.ai.provider.name)")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(theme.accent2)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 12) {
            Text("准备就绪").font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(theme.accentGradient)
            Text("⌘1–⌘6 切换面板 · ⌘K 无，⌘, 打开设置 · 边栏可收起\n随时在设置里重看本引导、改主题、配快捷键。")
                .font(.system(size: 12.5)).foregroundStyle(V.textDim)
                .multilineTextAlignment(.center).lineSpacing(3)
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Button("跳过") { finish() }
                .buttonStyle(.plain)
                .foregroundStyle(V.textDim)
                .font(.system(size: 12))

            Spacer()

            HStack(spacing: 7) {
                ForEach(0...lastStep, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.2)))
                        .frame(width: i == step ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
                }
            }

            Spacer()

            Button {
                if step < lastStep {
                    withAnimation { step += 1 }
                } else { finish() }
            } label: {
                Text(step < lastStep ? "下一步" : "开始使用")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 8)
            }
            .buttonStyle(.vitrineProminent)
        }
        .frame(maxWidth: 560)
    }

    private func finish() {
        Onboarding.seen = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onDone() }
    }
}

// MARK: - Bits

private struct OnbStat: View {
    var value: String; var label: String; var color: Color
    var numeric: Double? = nil
    var body: some View {
        VStack(spacing: 3) {
            Group {
                if let n = numeric {
                    CountingText(value: n, format: { "\(Int($0.rounded()))" },
                                 font: .system(size: 22, weight: .bold, design: .rounded))
                } else {
                    Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(color)
            Text(label).font(.system(size: 10)).foregroundStyle(V.textDim)
        }
        .frame(width: 74, height: 58)
        .background(color.opacity(0.1), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.22), lineWidth: 0.5))
    }
}

private struct OnbAIRow: View {
    var icon: String; var title: String; var detail: String
    var ok: Bool?; var tint: Color; var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(V.textDim)
                }
                Spacer()
                if let ok { Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? V.teal : V.amber).font(.system(size: 13)) }
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(V.textDim)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(hovering ? 0.08 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .onHover { hovering = $0 }
    }
}

// PrismMark (the shared brand glyph) now lives in Splash.swift, reused here and in the sidebar.
