import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = {
        if let raw = ProcessInfo.processInfo.environment["VITRINE_SETTINGS_TAB"],
           let t = Tab(rawValue: raw) { return t }
        return .appearance
    }()

    enum Tab: String, CaseIterable, Identifiable {
        case appearance, ai, shortcuts
        var id: String { rawValue }
        var title: String {
            switch self { case .appearance: "外观"; case .ai: "AI"; case .shortcuts: "快捷键" }
        }
        var symbol: String {
            switch self { case .appearance: "paintbrush"; case .ai: "sparkles"; case .shortcuts: "command" }
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.12)
                ScrollView {
                    Group {
                        switch tab {
                        case .appearance: AppearanceSettings()
                        case .ai: AISettingsPane()
                        case .shortcuts: ShortcutsSettings()
                        }
                    }
                    .padding(22)
                    .transition(.opacity)
                    .id(tab)
                    .animation(.spring(response: 0.35, dampingFraction: 0.9), value: tab)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(minWidth: 520, idealWidth: 660, maxWidth: 820,
               minHeight: 460, idealHeight: 640, maxHeight: 860)
        .escapeToDismiss(dismiss)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("设置")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Spacer()
            HStack(spacing: 4) {
                ForEach(Tab.allCases) { t in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = t }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: t.symbol).font(.system(size: 10, weight: .semibold))
                            Text(t.title).font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tab == t ? .primary : V.textDim)
                    .background {
                        if tab == t { Capsule().fill(.white.opacity(0.001)).vitrineGlassCapsule() }
                    }
                }
            }
            .padding(4)
            .vitrineGlassCapsule(tintStrength: 0.4)

            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .frame(width: 26, height: 26)
            .background(.primary.opacity(0.08), in: .circle)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var theme = theme
        VStack(alignment: .leading, spacing: 16) {
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("新手引导").font(.system(size: 13, weight: .semibold))
                        Text("重看开场引导，快速熟悉主题与 AI 配置")
                            .font(.system(size: 11)).foregroundStyle(V.textDim)
                    }
                    Spacer()
                    Button {
                        ui.replayOnboarding = true
                        dismiss()
                    } label: {
                        Label("重看引导", systemImage: "sparkles").font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.vitrineProminent)
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "主题", subtitle: "含 Apple / GitHub 等风格 —— 材质、背景、圆角、边框整套不同，非简单换色")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                        ForEach(Palettes.all) { p in
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    theme.paletteID = p.id
                                }
                            } label: {
                                ThemeSwatch(palette: p, selected: theme.paletteID == p.id)
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(theme.paletteID == p.id ? 1.03 : 1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: theme.paletteID)
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(title: "玻璃与分离度", subtitle: "调节 Liquid Glass 的通透度与卡片边框")
                    Knob(label: "玻璃通透度", detail: "低=更清透 · 高=更磨砂",
                         value: $theme.glassOpacity, symbol: "circle.lefthalf.filled")
                    Knob(label: "边框分离度", detail: "增强卡片之间的边界",
                         value: $theme.borderStrength, symbol: "square.dashed")
                    Knob(label: "极光活跃度", detail: "背景光晕的亮度与流动",
                         value: $theme.auroraIntensity, symbol: "sparkles")
                }
            }

            GlassCard(tint: theme.accent1) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "实时预览")
                    HStack(spacing: 10) {
                        ForEach(Palettes.by(theme.paletteID).aurora.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Palettes.by(theme.paletteID).aurora[i])
                                .frame(height: 34)
                        }
                    }
                    HStack {
                        GlassChip(text: "示例标签", color: theme.accent1, systemImage: "tag")
                        GlassChip(text: "强调", color: theme.accent2, systemImage: "star")
                        Spacer()
                        Text("边框与通透度随旋钮实时变化")
                            .font(.system(size: 10.5)).foregroundStyle(V.textDim)
                    }
                }
            }
        }
    }
}

private struct Knob: View {
    var label: String
    var detail: String
    @Binding var value: Double
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(V.textDim)
                Text(label).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(V.textDim)
                    .contentTransition(.numericText())
            }
            Slider(value: $value, in: 0...1)
                .controlSize(.small)
            Text(detail).font(.system(size: 10)).foregroundStyle(V.textDim)
        }
    }
}

// MARK: - AI

private struct AISettingsPane: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @State private var showKey = false
    @State private var pulling = false
    @State private var pullMsg: (String, Bool)?
    @State private var testing = false
    @State private var testResult: (conn: Bool?, connMsg: String, chat: Bool?, chatMsg: String)?

    private var localProviders: [AIProviderPreset] {
        [AIProviders.localClaude] + AIProviders.external.filter { AIProviders.localIDs.contains($0.id) }
    }
    private var cloudProviders: [AIProviderPreset] {
        AIProviders.external.filter { !AIProviders.localIDs.contains($0.id) }
    }

    var body: some View {
        @Bindable var store = store
        let ai = store.ai
        return VStack(alignment: .leading, spacing: 16) {
            statusBanner(ai)

            // Step 1 — pick a provider, grouped local vs cloud
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    stepHeader(1, "选择服务商", "本地推理隐私零成本；云端质量更高、需 API Key")
                    providerGroup("本地推理", "desktopcomputer", localProviders, ai)
                    providerGroup("云端 API", "cloud", cloudProviders, ai)
                }
            }

            // Step 2 — configure the chosen provider
            if ai.providerID == "ollama" {
                OllamaPanel()
            } else if ai.providerID == "llamacpp" {
                LlamaCppPanel()
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        stepHeader(2, "配置 · \(ai.provider.name)", configHint(ai))
                        if ai.isLocalClaude {
                            HStack {
                                Image(systemName: store.claudePath != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(store.claudePath != nil ? V.teal : V.amber)
                                Text(store.claudePath ?? "未检测到 claude —— 请先安装 Claude Code")
                                    .font(.vMono).foregroundStyle(theme.textDim).lineLimit(1)
                            }
                            modelField
                        } else {
                            Field(label: "Base URL", text: bindingEndpoint,
                                  placeholder: ai.provider.baseURL.isEmpty ? "https://…/v1" : ai.provider.baseURL)
                            keyField
                            modelField
                        }
                    }
                }
            }

            // Step 3 — verify
            GlassCard(tint: V.teal) {
                VStack(alignment: .leading, spacing: 12) {
                    stepHeader(3, "测试连接", "先测连通（GET /models）再验证模型（chat）")
                    HStack {
                        Button {
                            testing = true; testResult = nil
                            let cfg = ai.snapshot()
                            Task {
                                let r = await AIClient.test(cfg)
                                await MainActor.run {
                                    testResult = (r.connOK, r.connMsg, r.chatOK, r.chatMsg)
                                    testing = false
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if testing { ProgressView().controlSize(.small) }
                                else { Image(systemName: "checkmark.shield") }
                                Text("测试连接").font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.vitrineProminent)
                        .disabled(testing)
                        Spacer()
                    }
                    if let r = testResult {
                        StepRow(ok: r.conn, label: "连通", msg: r.connMsg)
                        StepRow(ok: r.chat, label: "模型", msg: r.chatMsg)
                    }
                }
            }

            // Smart titles — non-destructive title layer
            GlassCard(tint: V.violet) {
                VStack(alignment: .leading, spacing: 12) {
                    stepHeader(4, "智能标题", "弱标题默认已用结构启发式修复；AI 标题可选，默认用 Haiku（快而省），均不覆盖原始标题")
                    Toggle(isOn: $store.useSmartTitles) {
                        Text("对所有会话使用智能标题").font(.system(size: 12, weight: .medium))
                    }
                    .toggleStyle(.switch).controlSize(.small)
                    Toggle(isOn: $store.autoSmartTitles) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("扫描后自动补齐弱标题").font(.system(size: 12, weight: .medium))
                            Text("后台增量生成最近弱标题（跳过噪音会话，省 token），标题就位时有微光过渡")
                                .font(.system(size: 10)).foregroundStyle(theme.textDim)
                        }
                    }
                    .toggleStyle(.switch).controlSize(.small)
                    HStack(spacing: 10) {
                        Button {
                            Task { await store.generateSmartTitles() }
                        } label: {
                            HStack(spacing: 6) {
                                if store.titlingBusy { ProgressView().controlSize(.small) }
                                else { Image(systemName: "sparkles") }
                                Text(store.titlingBusy
                                     ? "生成中 \(store.titleDone)/\(store.titleTotal)"
                                     : "AI 生成弱标题（\(store.pendingTitleCount) 条）")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.vitrineProminent)
                        .disabled(!store.aiAvailable || store.titlingBusy || store.pendingTitleCount == 0)
                        if store.titlingBusy {
                            Button("取消") { store.cancelTitling() }.buttonStyle(.vitrine)
                        }
                        Spacer()
                    }
                    if store.titlingBusy {
                        ProgressView(value: Double(store.titleDone), total: Double(max(1, store.titleTotal)))
                            .tint(V.violet)
                    }
                }
            }

            Text("AI 用于会话总结、项目洞察、技能蒸馏、智能标题。API Key 明文存于本机 UserDefaults，首次会尝试从 OPENAI_API_KEY 或 ~/.codex/auth.json 预填。")
                .font(.system(size: 10)).foregroundStyle(theme.textDim)
        }
    }

    // MARK: guided pieces

    private func statusBanner(_ ai: AISettings) -> some View {
        let ready = store.aiAvailable
        let c = ready ? V.teal : V.amber
        return HStack(spacing: 10) {
            Image(systemName: ready ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18)).foregroundStyle(c)
            VStack(alignment: .leading, spacing: 1) {
                Text(ready ? "AI 已就绪" : "AI 未配置")
                    .font(theme.display(13, .semibold)).foregroundStyle(theme.textStrong)
                Text(ready ? "\(ai.provider.name)\(ai.isLocalClaude || ai.model.isEmpty ? "" : " · \(ai.model)")"
                           : "下方选择并配置一个服务商")
                    .font(.system(size: 11)).foregroundStyle(theme.textDim).lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(c.opacity(0.10), in: .rect(cornerRadius: V.corner))
        .overlay(RoundedRectangle(cornerRadius: V.corner, style: .continuous).strokeBorder(c.opacity(0.25), lineWidth: 1))
    }

    private func stepHeader(_ n: Int, _ title: String, _ hint: String) -> some View {
        HStack(spacing: 9) {
            Text("\(n)").font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(theme.accentGradient, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(theme.display(14, .semibold)).foregroundStyle(theme.textStrong)
                Text(hint).font(.system(size: 10.5)).foregroundStyle(theme.textDim)
            }
            Spacer()
        }
    }

    private func providerGroup(_ label: String, _ icon: String, _ items: [AIProviderPreset], _ ai: AISettings) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(label, systemImage: icon)
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.textDim)
                .textCase(.uppercase)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                ForEach(items) { p in
                    ProviderChip(preset: p, selected: ai.providerID == p.id) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            ai.applyProvider(p); testResult = nil; pullMsg = nil
                        }
                    }
                }
            }
        }
    }

    private func configHint(_ ai: AISettings) -> String {
        ai.isLocalClaude ? "直接调用已登录的 claude 命令，无需 API Key" : "填入 Base URL、API Key 与模型 ID"
    }

    private var bindingEndpoint: Binding<String> {
        Binding(get: { store.ai.endpoint }, set: { store.ai.endpoint = $0 })
    }
    private var bindingKey: Binding<String> {
        Binding(get: { store.ai.apiKey }, set: { store.ai.apiKey = $0 })
    }
    private var bindingModel: Binding<String> {
        Binding(get: { store.ai.model }, set: { store.ai.model = $0 })
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("API Key").font(.system(size: 11, weight: .medium)).foregroundStyle(V.textDim)
            HStack(spacing: 8) {
                Group {
                    if showKey { TextField("sk-…", text: bindingKey) }
                    else { SecureField("sk-…", text: bindingKey) }
                }
                .textFieldStyle(.plain).font(.vMono)
                Button { showKey.toggle() } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye").font(.system(size: 11))
                        .foregroundStyle(V.textDim)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .vitrineGlass(corner: 10, tintStrength: 0.3)
        }
    }

    private var modelField: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("模型").font(.system(size: 11, weight: .medium)).foregroundStyle(V.textDim)
                Spacer()
                if !store.ai.isLocalClaude {
                    Button {
                        pulling = true; pullMsg = nil
                        let cfg = store.ai.snapshot()
                        Task {
                            do {
                                let models = try await AIClient.listModels(cfg)
                                await MainActor.run {
                                    store.ai.availableModels = models
                                    pullMsg = ("拉取到 \(models.count) 个模型", false)
                                }
                            } catch {
                                await MainActor.run { pullMsg = (error.localizedDescription, true) }
                            }
                            await MainActor.run { pulling = false }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if pulling { ProgressView().controlSize(.mini) }
                            else { Image(systemName: "arrow.down.circle").font(.system(size: 10)) }
                            Text("拉取模型").font(.system(size: 10.5, weight: .semibold))
                        }
                    }
                    .buttonStyle(.vitrine)
                    .disabled(pulling || store.ai.endpoint.isEmpty)
                }
            }
            HStack(spacing: 8) {
                TextField(store.ai.provider.modelHint.isEmpty ? "模型 ID" : store.ai.provider.modelHint,
                          text: bindingModel)
                    .textFieldStyle(.plain).font(.vMono)
                if !store.ai.availableModels.isEmpty {
                    Menu {
                        ForEach(store.ai.availableModels, id: \.self) { m in
                            Button(m) { store.ai.model = m }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle").font(.system(size: 12))
                    }
                    .menuStyle(.borderlessButton).frame(width: 22)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .vitrineGlass(corner: 10, tintStrength: 0.3)
            if let (msg, isErr) = pullMsg {
                Text(msg).font(.system(size: 10)).foregroundStyle(isErr ? V.rose : V.teal)
            }
        }
    }
}

private struct Field: View {
    var label: String
    @Binding var text: String
    var placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(V.textDim)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).font(.vMono)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .vitrineGlass(corner: 10, tintStrength: 0.3)
        }
    }
}

private struct ProviderChip: View {
    var preset: AIProviderPreset
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: preset.id == "local-claude" ? "terminal" : "cloud")
                    .font(.system(size: 11, weight: .semibold))
                Text(preset.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
            }
            .foregroundStyle(selected ? .primary : V.textDim)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .contentShape(.rect)
        }
        .pressable()
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.001)).vitrineGlass(corner: 10)
            } else {
                RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .hoverLift(1.03)
    }
}

private struct StepRow: View {
    var ok: Bool?
    var label: String
    var msg: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: ok == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(ok == true ? V.teal : V.rose)
            Text(msg.isEmpty ? label : "\(label)：\(msg)")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

// MARK: - Local engine panels

/// Ollama = local llama.cpp runtime with native model pulling.
private struct OllamaPanel: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let engine = store.localEngine
        let ai = store.ai
        return VStack(spacing: 14) {
            GlassCard(tint: engine.ollamaUp ? V.teal : V.amber) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader(title: "Ollama 引擎", subtitle: "本地 llama.cpp 推理 · localhost:11434")
                        Spacer()
                        HStack(spacing: 6) {
                            if engine.ollamaUp {
                                LivePulse(color: V.teal, size: 8)
                            } else {
                                Circle().fill(engine.ollamaInstalled ? V.amber : V.rose)
                                    .frame(width: 8, height: 8)
                            }
                            Text(engine.ollamaUp ? "运行中" : (engine.ollamaInstalled ? "未启动" : "未安装"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(V.textDim)
                        }
                    }
                    HStack {
                        Button {
                            Task { await engine.refresh() }
                        } label: { Label("刷新", systemImage: "arrow.clockwise").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(.vitrine)
                        if engine.ollamaInstalled && !engine.ollamaUp {
                            Button {
                                Task { await engine.startOllama() }
                            } label: { Label("启动服务", systemImage: "play.fill").font(.system(size: 11, weight: .semibold)) }
                            .buttonStyle(.vitrineProminent)
                        }
                        if engine.checking { ProgressView().controlSize(.small) }
                        Spacer()
                        if !engine.ollamaInstalled {
                            Text("brew install ollama").font(.vMono).foregroundStyle(V.textDim)
                        }
                    }
                }
            }

            // Local models
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "本地模型", subtitle: "点击选用 · 共 \(engine.ollamaModels.count) 个")
                    if engine.ollamaModels.isEmpty {
                        Text(engine.ollamaUp ? "还没有本地模型 —— 在下方拉取一个" : "启动 Ollama 后显示")
                            .font(.system(size: 11)).foregroundStyle(V.textDim)
                    }
                    ForEach(engine.ollamaModels) { m in
                        Button {
                            ai.endpoint = "http://localhost:11434/v1"
                            ai.model = m.name
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: ai.model == m.name ? "checkmark.circle.fill" : "cube")
                                    .font(.system(size: 12))
                                    .foregroundStyle(ai.model == m.name ? V.teal : V.textDim)
                                Text(m.name).font(.system(size: 12, weight: .medium))
                                Spacer()
                                if !m.paramSize.isEmpty { GlassChip(text: m.paramSize, color: V.violet) }
                                Text(m.sizeLabel).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(V.textDim)
                            }
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .contentShape(.rect)
                            .background(ai.model == m.name ? V.teal.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Pull
            GlassCard(tint: V.violet) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "拉取模型", subtitle: "例如 qwen2.5:7b · llama3.2:3b · gemma2:9b")
                    HStack(spacing: 8) {
                        TextField("模型名（Ollama 库）", text: Binding(
                            get: { engine.pullName }, set: { engine.pullName = $0 }))
                            .textFieldStyle(.plain).font(.vMono)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .vitrineGlass(corner: 10, tintStrength: 0.3)
                        if engine.pulling {
                            Button { engine.cancelPull() } label: {
                                Label("取消", systemImage: "stop.fill").font(.system(size: 11, weight: .semibold))
                            }.buttonStyle(.vitrine)
                        } else {
                            Button { engine.startPull(engine.pullName) } label: {
                                Label("拉取", systemImage: "arrow.down.circle").font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.vitrineProminent)
                            .disabled(engine.pullName.isEmpty || !engine.ollamaUp)
                        }
                    }
                    if let p = engine.pullProgress {
                        VStack(alignment: .leading, spacing: 4) {
                            if p.fraction >= 0 {
                                ProgressView(value: p.fraction).tint(V.violet)
                            } else if engine.pulling {
                                ProgressView().controlSize(.small)
                            }
                            Text(p.fraction >= 0 ? "\(p.status) · \(Int(p.fraction * 100))%" : p.status)
                                .font(.system(size: 10)).foregroundStyle(V.textDim).lineLimit(1)
                        }
                    }
                }
            }
        }
        .task { await engine.refresh() }
    }
}

/// llama.cpp llama-server: spawn a chosen GGUF and chat through its OpenAI endpoint.
private struct LlamaCppPanel: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let engine = store.localEngine
        let llama = engine.llama
        let ai = store.ai
        return GlassCard(tint: running(llama) ? V.teal : V.amber) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "llama.cpp (llama-server)", subtitle: "直接加载 GGUF 权重本地推理")
                    Spacer()
                    Text(stateLabel(llama.state))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(running(llama) ? V.teal : V.textDim)
                }
                HStack {
                    Image(systemName: llama.installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(llama.installed ? V.teal : V.amber)
                    Text(llama.binaryPath ?? "未找到 llama-server（brew install llama.cpp）")
                        .font(.vMono).foregroundStyle(V.textDim).lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("GGUF 路径").font(.system(size: 11, weight: .medium)).foregroundStyle(V.textDim)
                    TextField("~/models/qwen2.5-7b-instruct-q4_k_m.gguf", text: Binding(
                        get: { ai.ggufPath }, set: { ai.ggufPath = $0 }))
                        .textFieldStyle(.plain).font(.vMono)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .vitrineGlass(corner: 10, tintStrength: 0.3)
                }
                HStack {
                    Text("端口").font(.system(size: 11)).foregroundStyle(V.textDim)
                    TextField("8080", value: Binding(get: { ai.llamaPort }, set: { ai.llamaPort = $0 }), format: .number)
                        .textFieldStyle(.plain).font(.vMono).frame(width: 70)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .vitrineGlass(corner: 8, tintStrength: 0.3)
                    Spacer()
                    if running(llama) {
                        Button { llama.stop() } label: {
                            Label("停止", systemImage: "stop.fill").font(.system(size: 11, weight: .semibold))
                        }.buttonStyle(.vitrine)
                    } else {
                        Button {
                            llama.start(ggufPath: ai.ggufPath, port: ai.llamaPort)
                            ai.endpoint = "http://127.0.0.1:\(ai.llamaPort)/v1"
                            if ai.model.isEmpty { ai.model = (ai.ggufPath as NSString).lastPathComponent }
                        } label: {
                            Label("启动引擎", systemImage: "play.fill").font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.vitrineProminent)
                        .disabled(!llama.installed || ai.ggufPath.isEmpty)
                    }
                }
                if case .starting = llama.state {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("启动中，等待 /health…").font(.system(size: 10.5)).foregroundStyle(V.textDim) }
                }
                if case .failed(let msg) = llama.state {
                    Label(msg, systemImage: "exclamationmark.triangle.fill").font(.system(size: 10.5)).foregroundStyle(V.rose)
                }
                if running(llama) {
                    Label("已在 \(ai.endpoint) 提供服务，可直接测试连接", systemImage: "checkmark.seal")
                        .font(.system(size: 10.5)).foregroundStyle(V.teal)
                }
            }
        }
    }

    private func running(_ l: LlamaServer) -> Bool { if case .running = l.state { return true }; return false }
    private func stateLabel(_ s: LlamaServer.State) -> String {
        switch s {
        case .stopped: "已停止"
        case .starting: "启动中"
        case .running(let p): "运行中 :\(p)"
        case .failed: "失败"
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsSettings: View {
    @Bindable private var keys = KeybindingManager.shared
    @State private var recording: KeyAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader(title: "键盘快捷键", subtitle: "点击右侧胶囊后按下新的组合键 · ⌘ 组合最稳")
                        Spacer()
                        Button { keys.resetAll() } label: {
                            Label("全部重置", systemImage: "arrow.counterclockwise").font(.system(size: 11, weight: .semibold))
                        }.buttonStyle(.vitrine)
                    }
                    ForEach(KeyAction.allCases) { action in
                        ShortcutRow(action: action,
                                    binding: keys.binding(action),
                                    recording: recording == action,
                                    conflict: keys.conflict(action, keys.binding(action)),
                                    onRecordToggle: { recording = (recording == action) ? nil : action },
                                    onCaptured: { b in
                                        keys.set(action, b); recording = nil
                                    },
                                    onReset: { keys.reset(action) })
                    }
                }
            }
            Text("修改立即生效于菜单栏「视图」。少数系统占用的组合（如 ⌘Q/⌘W）不建议覆盖。")
                .font(.system(size: 10)).foregroundStyle(V.textDim)
        }
    }
}

private struct ShortcutRow: View {
    var action: KeyAction
    var binding: Keybinding
    var recording: Bool
    var conflict: KeyAction?
    var onRecordToggle: () -> Void
    var onCaptured: (Keybinding) -> Void
    var onReset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(action.title).font(.system(size: 12.5, weight: .medium))
            if let c = conflict {
                GlassChip(text: "与「\(c.title)」冲突", color: V.amber, systemImage: "exclamationmark.triangle")
            }
            Spacer()
            if recording {
                KeyCapture(onCaptured: onCaptured)
                    .frame(width: 130, height: 30)
            } else {
                Button(action: onRecordToggle) {
                    Text(binding.display.isEmpty ? "未设置" : binding.display)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 108, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            }
            Button(action: onReset) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                    .foregroundStyle(V.textDim)
            }
            .buttonStyle(.plain)
            .help("恢复默认")
        }
        .padding(.vertical, 3)
    }
}

/// Captures one keystroke via a local NSEvent monitor and reports the chord.
private struct KeyCapture: NSViewRepresentable {
    var onCaptured: (Keybinding) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = CaptureView()
        v.onCaptured = onCaptured
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class CaptureView: NSView {
        var onCaptured: ((Keybinding) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                var mods = 0
                let f = event.modifierFlags
                if f.contains(.command) { mods |= Int(EventModifiers.command.rawValue) }
                if f.contains(.option) { mods |= Int(EventModifiers.option.rawValue) }
                if f.contains(.control) { mods |= Int(EventModifiers.control.rawValue) }
                if f.contains(.shift) { mods |= Int(EventModifiers.shift.rawValue) }
                let chars = event.charactersIgnoringModifiers ?? ""
                guard let ch = chars.first, ch.isLetter || ch.isNumber || ch == "," || ch == "." || ch == "/" else {
                    return nil  // ignore pure-modifier / non-bindable keys
                }
                self.onCaptured?(Keybinding(key: String(ch).lowercased(), modifiers: mods))
                return nil
            }
        }

        override func removeFromSuperview() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
            super.removeFromSuperview()
        }
        override var acceptsFirstResponder: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            NSColor(white: 1, alpha: 0.10).setFill()
            let p = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
            p.fill()
            let s = "按下组合键…"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor]
            let size = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
        }
    }
}
