import SwiftUI

struct DistilleryView: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @State private var projectPath: String?
    @State private var evidence: SkillEvidence?
    @State private var skillText = ""
    @State private var skillName = ""
    @State private var origin = ""
    @State private var target: InjectionTarget = .claudeSkills
    @State private var focus: DistillFocus = .all
    @State private var distillingAI = false
    @State private var message: (String, Bool)?   // (text, isError)
    @State private var didAutoDistill = false

    private var project: ProjectAggregate? {
        store.projects.first { $0.path == projectPath }
    }

    private func runHeuristic() {
        guard let p = project else { return }
        let e = Distiller.analyze(project: p)
        let skill = Distiller.heuristicSkill(e, projectName: p.name)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            evidence = e
            skillText = skill.body
            skillName = skill.name
            origin = "启发式"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("技能蒸馏").themedDisplay(24)
                    Text("从项目的全部会话中提取开发规范、常用脚本与工作范式，蒸馏为可注入任意 Agent 的 SKILL.md")
                        .font(.system(size: 12)).foregroundStyle(V.textDim)
                }
                .padding(.top, 26)

                // Project picker + actions
                GlassCard(padding: 14) {
                    HStack(spacing: 12) {
                        Picker("项目", selection: $projectPath) {
                            Text("选择项目…").tag(String?.none)
                            ForEach(store.projects) { p in
                                Text("\(p.name)（\(p.sessions.count) 会话）").tag(String?.some(p.path))
                            }
                        }
                        .frame(maxWidth: 300)

                        HStack(spacing: 5) {
                            Image(systemName: "scope").font(.system(size: 10)).foregroundStyle(V.textDim)
                            Picker("侧重", selection: $focus) {
                                ForEach(DistillFocus.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 216)
                            .help("引导 AI 深度蒸馏的侧重点")
                        }

                        Spacer()
                        Button {
                            runHeuristic()
                        } label: {
                            Label("启发式蒸馏", systemImage: "bolt")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .buttonStyle(.vitrine)
                        .disabled(project == nil)

                        Button {
                            guard let p = project else { return }
                            distillingAI = true
                            message = nil
                            let e = evidence ?? Distiller.analyze(project: p)
                            evidence = e
                            let cfg = store.ai.snapshot()
                            Task {
                                do {
                                    let out = try await AIClient.chat(
                                        cfg,
                                        system: "你是一个 Agent 技能蒸馏器，直接输出 SKILL.md 全文，不要任何额外说明。" + focus.directive,
                                        user: Distiller.aiPrompt(e, projectName: p.name),
                                        maxTokens: 2200, timeout: 200)
                                    await MainActor.run {
                                        withAnimation {
                                            skillText = out.trimmingCharacters(in: .whitespacesAndNewlines)
                                            skillName = Distiller.slugify(p.name) + "-playbook"
                                            origin = "AI"
                                        }
                                    }
                                } catch {
                                    await MainActor.run {
                                        message = ("AI 蒸馏失败：\(error.localizedDescription)（可先用启发式蒸馏）", true)
                                    }
                                }
                                await MainActor.run { distillingAI = false }
                            }
                        } label: {
                            if distillingAI {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("蒸馏中…").font(.system(size: 11.5, weight: .semibold))
                                }
                            } else {
                                Label("AI 深度蒸馏", systemImage: "wand.and.stars")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                        }
                        .buttonStyle(.vitrineProminent)
                        .disabled(project == nil || distillingAI || !store.aiAvailable)
                    }
                }

                // Evidence
                if let e = evidence {
                    HStack(alignment: .top, spacing: 14) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "高频命令", subtitle: "跨 \(e.sessionCount) 个会话统计",
                                              icon: "terminal", iconColor: V.teal)
                                ForEach(Array(e.topCommands.prefix(9).enumerated()), id: \.element.0) { i, pair in
                                    HStack(spacing: 8) {
                                        Syntax.line(pair.0, size: 11.5).lineLimit(1)
                                        Spacer()
                                        CountingText(value: Double(pair.1), format: { "×\(Int($0.rounded()))" },
                                                     font: .system(size: 10, weight: .bold, design: .rounded),
                                                     key: "cmd-\(pair.0)")
                                            .foregroundStyle(V.teal)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(theme.well.opacity(0.6), in: .rect(cornerRadius: 7))
                                    .hoverLift(1.01)
                                    .appearStagger(i, trigger: e.sessionCount)
                                }
                            }
                        }
                        .appearStagger(0, trigger: e.sessionCount)
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "侦测到的规范与范式")
                                if e.conventions.isEmpty {
                                    Text("未侦测到明显规范").font(.system(size: 11)).foregroundStyle(V.textDim)
                                }
                                ForEach(Array(e.conventions.enumerated()), id: \.element) { i, c in
                                    Label(c, systemImage: "checkmark.seal")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .appearStagger(i, trigger: e.sessionCount)
                                }
                                if !e.topTools.isEmpty {
                                    Divider().opacity(0.2)
                                    SectionHeader(title: "工具画像")
                                    FlowChips(items: e.topTools.map { "\($0.0)×\($0.1)" })
                                }
                            }
                        }
                        .appearStagger(1, trigger: e.sessionCount)
                    }
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }

                // Skill editor + injection
                if !skillText.isEmpty {
                    GlassCard(tint: V.violet) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SectionHeader(title: "SKILL.md（\(origin)蒸馏 · 可编辑）",
                                              subtitle: "技能名：\(skillName)")
                                Spacer()
                                Picker("", selection: $target) {
                                    ForEach(InjectionTarget.allCases) { t in
                                        Label(t.display, systemImage: t.agent.symbol).tag(t)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 280)
                                Button {
                                    CLI.copyToPasteboard(skillText)
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc").font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.vitrine)
                                Button {
                                    let skill = DistilledSkill(name: skillName, description: "",
                                                               body: skillText, origin: origin)
                                    do {
                                        let path = try Distiller.inject(skill, target: target,
                                                                        projectPath: projectPath)
                                        withAnimation { message = ("已注入：\(path)", false) }
                                    } catch {
                                        withAnimation { message = ("注入失败：\(error.localizedDescription)", true) }
                                    }
                                } label: {
                                    Label("注入", systemImage: "syringe")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.vitrineProminent)
                            }
                            TextEditor(text: $skillText)
                                .font(.vMono)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .frame(minHeight: 260, maxHeight: 380)
                                .background(theme.well, in: .rect(cornerRadius: 12))
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }

                if let (text, isError) = message {
                    Label(text, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(isError ? V.rose : V.teal)
                        .transition(.opacity)
                }

                if evidence == nil {
                    EmptyHint(symbol: "flask",
                              text: "选择项目后点击「启发式蒸馏」——\n从真实会话行为中提炼出可复用的技能")
                        .frame(height: 240)
                }
            }
            .padding(22)
            .centeredContent()
        }
        .scrollIndicators(.never)
        .onAppear {
            if projectPath == nil { projectPath = store.projects.first?.path }
            maybeAutoDistill()
        }
        .onChange(of: store.projects.count) { maybeAutoDistill() }
    }

    /// Debug affordance: VITRINE_DISTILL_PROJECT auto-selects a project and distills once loaded.
    private func maybeAutoDistill() {
        guard !didAutoDistill,
              let hint = ProcessInfo.processInfo.environment["VITRINE_DISTILL_PROJECT"],
              let match = store.projects.first(where: { $0.name.contains(hint) || $0.path.contains(hint) })
        else { return }
        didAutoDistill = true
        projectPath = match.path
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { runHeuristic() }
    }
}

/// Simple wrapping chip row.
struct FlowChips: View {
    var items: [String]
    var body: some View {
        var rows: [[String]] = [[]]
        var count = 0
        for item in items {
            if count + item.count > 42 { rows.append([]); count = 0 }
            rows[rows.count - 1].append(item)
            count += item.count + 3
        }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { GlassChip(text: $0, color: V.sky) }
                }
            }
        }
    }
}
