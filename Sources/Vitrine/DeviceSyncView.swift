import SwiftUI

/// Settings ▸ 多设备同步. Device identity + hardware fingerprint, a git-backed remote the user
/// configures and owns, and a manual "sync now" — nothing here ever runs on its own.
struct SyncSettingsPane: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @State private var showToken = false
    @State private var knownDevices: [DeviceSnapshot] = []

    var body: some View {
        @Bindable var sync = store.sync
        VStack(alignment: .leading, spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "本机设备",
                                  subtitle: "同步后，其他设备能看到这台机器的名字、硬件与统计概览 —— 不含任何会话内容或路径",
                                  icon: "desktopcomputer", iconColor: V.violet)
                    Field(label: "设备名称", text: $sync.deviceName, placeholder: DeviceIdentity.defaultName)
                    let d = DeviceIdentity.current()
                    HStack(spacing: 6) {
                        GlassChip(text: d.os, color: V.sky, systemImage: "apple.logo")
                        GlassChip(text: d.cpu, color: V.teal, systemImage: "cpu")
                        GlassChip(text: d.gpu, color: V.amber, systemImage: "aqi.medium")
                        GlassChip(text: "\(Int(d.ramGB)) GB 内存", color: V.rose, systemImage: "memorychip")
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Git 仓库", subtitle: "建议新建一个私有仓库专门存放设备快照，不要和项目代码混用")
                    Field(label: "仓库地址（HTTPS）", text: $sync.remoteURL,
                          placeholder: "https://gitlab.com/you/vitrine-sync.git")
                    tokenField(sync: sync)
                    Text("每次同步只上传一份聚合统计 JSON（会话数 / 项目数 / tokens / 预估花费 / Agent 占比），"
                       + "永远不包含提示词、转录或具体文件路径。推送前请自行确认该仓库是私有的 —— Vitrine 不会替你创建或校验仓库权限。")
                        .font(.system(size: 10)).foregroundStyle(theme.textDim)
                }
            }

            GlassCard(tint: V.teal) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "立即同步",
                                  subtitle: sync.lastSyncAt.map { "上次同步：\(Fmt.relative($0))" } ?? "尚未同步过",
                                  icon: "arrow.triangle.2.circlepath", iconColor: V.teal)
                    HStack {
                        Button {
                            Task {
                                await store.syncNow()
                                knownDevices = GitSync.knownDevices()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if sync.syncing { ProgressView().controlSize(.small) }
                                else { Image(systemName: "arrow.up.circle") }
                                Text(sync.syncing ? "同步中…" : "同步这台设备").font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.vitrineProminent)
                        .disabled(sync.syncing || sync.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }
                    if let r = sync.lastResult {
                        Label(r.message, systemImage: r.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(r.isError ? V.rose : V.teal)
                            .lineLimit(3)
                    }
                }
            }

            if !knownDevices.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "已知设备", subtitle: "来自上次拉取到的仓库快照")
                        ForEach(knownDevices, id: \.device.id) { snap in
                            DeviceRow(snapshot: snap, isThisDevice: snap.device.id == DeviceIdentity.id)
                        }
                    }
                }
            }
        }
        .onAppear { knownDevices = GitSync.knownDevices() }
    }

    private func tokenField(sync: SyncSettings) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Access Token").font(.system(size: 11, weight: .medium)).foregroundStyle(V.textDim)
                Spacer()
                Text("存于 macOS 钥匙串，不落盘明文").font(.system(size: 9.5)).foregroundStyle(theme.textFaint)
            }
            HStack(spacing: 8) {
                Group {
                    if showToken {
                        TextField("glpat-…", text: Binding(get: { sync.token }, set: { sync.token = $0 }))
                    } else {
                        SecureField("glpat-…", text: Binding(get: { sync.token }, set: { sync.token = $0 }))
                    }
                }
                .textFieldStyle(.plain).font(.vMono)
                Button { showToken.toggle() } label: {
                    Image(systemName: showToken ? "eye.slash" : "eye").font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(V.textDim)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .vitrineGlass(corner: 10, tintStrength: 0.3)
        }
    }
}

private struct DeviceRow: View {
    var snapshot: DeviceSnapshot
    var isThisDevice: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 13)).foregroundStyle(isThisDevice ? V.teal : V.textDim)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(snapshot.device.name).font(.system(size: 12.5, weight: .semibold))
                    if isThisDevice { GlassChip(text: "本机", color: V.teal) }
                }
                Text("\(snapshot.device.cpu) · \(snapshot.device.gpu) · \(Int(snapshot.device.ramGB))GB")
                    .font(.system(size: 10)).foregroundStyle(V.textDim).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(snapshot.sessionCount) 会话 · " + CostFmt.usd(snapshot.estimatedCostUSD))
                    .font(.system(size: 11, weight: .medium))
                Text(Fmt.relative(snapshot.syncedAt)).font(.system(size: 10)).foregroundStyle(V.textDim)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 10))
    }
}
