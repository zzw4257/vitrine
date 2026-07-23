import Foundation
import Observation
#if canImport(Metal)
import Metal
#endif
import Security

// MARK: - This device's identity + hardware fingerprint

/// What one device publishes about itself — an aggregate snapshot, never raw transcripts or
/// prompts, matching Vitrine's local-first/read-only invariant even when syncing is opted into.
struct DeviceInfo: Codable, Hashable {
    var id: String
    var name: String
    var os: String
    var cpu: String
    var gpu: String
    var ramGB: Double
}

struct DeviceSnapshot: Codable {
    var device: DeviceInfo
    var syncedAt: Date
    var sessionCount: Int
    var projectCount: Int
    var totalTokens: Int
    var estimatedCostUSD: Double
    var agentShare: [String: Int]
}

enum DeviceIdentity {
    private static let idKey = "vitrine.device.id"
    private static let nameKey = "vitrine.device.name"

    /// A stable id that survives renames — generated once, persisted forever.
    static var id: String {
        if let saved = UserDefaults.standard.string(forKey: idKey) { return saved }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: idKey)
        return fresh
    }

    static var name: String {
        get { UserDefaults.standard.string(forKey: nameKey) ?? defaultName }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    /// The name shown in System Settings ▸ Sharing, same as Finder's "About This Mac" default.
    static var defaultName: String { Host.current().localizedName ?? ProcessInfo.processInfo.hostName }

    static func current() -> DeviceInfo {
        let bytes = Double(ProcessInfo.processInfo.physicalMemory)
        return DeviceInfo(id: id, name: name, os: osVersion(), cpu: cpuBrand(), gpu: gpuName(),
                           ramGB: ((bytes / 1_073_741_824) * 10).rounded() / 10)
    }

    private static func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }

    private static func cpuBrand() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let s = String(cString: buf).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "Apple Silicon" : s
    }

    private static func gpuName() -> String {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice()?.name ?? "未知 GPU"
        #else
        return "未知 GPU"
        #endif
    }
}

// MARK: - Keychain (the GitLab token is more sensitive than the AI provider key, so unlike
// AISettings.apiKey it does NOT live in plain UserDefaults — Keychain Services needs no
// third-party dependency, keeping Vitrine's zero-deps invariant intact)

enum Keychain {
    private static func query(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func set(_ value: String, service: String, account: String) {
        var q = query(service, account)
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(service: String, account: String) -> String? {
        var q = query(service, account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Sync settings (persisted config; the token lives in Keychain, not here)

@Observable
final class SyncSettings {
    private static let keychainService = "com.zzw4257.vitrine.gitlab-sync"
    private static let keychainAccount = "token"

    var remoteURL: String { didSet { UserDefaults.standard.set(remoteURL, forKey: "vitrine.sync.remote") } }
    var deviceName: String { didSet { DeviceIdentity.name = deviceName } }
    var token: String { didSet { Keychain.set(token, service: Self.keychainService, account: Self.keychainAccount) } }

    var syncing = false
    var lastResult: (message: String, isError: Bool)?
    var lastSyncAt: Date? {
        get { UserDefaults.standard.object(forKey: "vitrine.sync.lastAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "vitrine.sync.lastAt") }
    }

    init() {
        remoteURL = UserDefaults.standard.string(forKey: "vitrine.sync.remote") ?? ""
        deviceName = DeviceIdentity.name
        token = Keychain.get(service: Self.keychainService, account: Self.keychainAccount) ?? ""
    }
}

// MARK: - Git-backed sync engine

/// Pushes ONE JSON file per device — an aggregate snapshot, never session content — to a GitLab
/// (or any git host) repo the user owns and configures themselves. Shells out to the system
/// `git`, same "drive a real CLI via Process" pattern Vitrine already uses for claude/ollama/etc.,
/// so no new dependency is introduced. Every call here is user-initiated (a button press) — never
/// automatic — per Vitrine's "the only writes are user-initiated" invariant, now extended to network.
enum GitSync {
    struct SyncError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static var repoDir: URL { ScanEngine.supportDir.appendingPathComponent("sync-repo") }

    @discardableResult
    private static func run(_ args: [String], cwd: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw SyncError(message: out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "git 退出码 \(p.terminationStatus)" : String(out.prefix(400)))
        }
        return out
    }

    /// Embeds the token as a GitLab/GitHub-style `oauth2:<token>@` basic-auth URL component for
    /// this one process invocation only — never written to disk (the remote URL git stores in
    /// .git/config is the UN-authenticated one; we always pass the authed form via `-c` instead).
    private static func authedURL(_ url: String, token: String) -> String {
        guard !token.isEmpty, url.hasPrefix("https://") else { return url }
        return url.replacingOccurrences(of: "https://", with: "https://oauth2:\(token)@")
    }

    private static func slug(_ s: String) -> String {
        let cleaned = String(s.map { $0.isLetter || $0.isNumber ? $0 : "-" }).lowercased()
        return cleaned.isEmpty ? "device" : cleaned
    }

    /// Clone-or-init the local mirror, write this device's snapshot, commit, and push. Runs off
    /// the main actor since every step shells out; returns a short human-readable status line.
    static func syncNow(remoteURL: String, token: String, snapshot: DeviceSnapshot) async throws -> String {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SyncError(message: "尚未配置 Git 仓库地址") }
        let dir = repoDir
        let authed = authedURL(trimmed, token: token)

        return try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                try run(["remote", "set-url", "origin", authed], cwd: dir)
                _ = try? run(["fetch", "origin"], cwd: dir)
                _ = try? run(["reset", "--hard", "origin/HEAD"], cwd: dir)
            } else {
                try? fm.removeItem(at: dir)
                try fm.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
                do {
                    try run(["clone", authed, dir.path], cwd: dir.deletingLastPathComponent())
                } catch {
                    // A brand-new/empty remote repo fails to clone — start local history instead.
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    try run(["init", "-b", "main"], cwd: dir)
                    try run(["remote", "add", "origin", authed], cwd: dir)
                }
            }

            let devicesDir = dir.appendingPathComponent("devices")
            try fm.createDirectory(at: devicesDir, withIntermediateDirectories: true)
            let file = devicesDir.appendingPathComponent(slug(snapshot.device.name) + ".json")
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(snapshot).write(to: file, options: .atomic)

            try run(["add", "-A"], cwd: dir)
            _ = try? run(["-c", "user.email=vitrine@local", "-c", "user.name=Vitrine",
                          "commit", "-m", "sync: \(snapshot.device.name) · \(ISO8601DateFormatter().string(from: Date()))"],
                         cwd: dir)
            try run(["push", "-u", "origin", "HEAD:main"], cwd: dir)
            return "已同步到 \(trimmed)"
        }.value
    }

    /// Read back every OTHER device's last-pushed snapshot from the local mirror (post-sync).
    static func knownDevices() -> [DeviceSnapshot] {
        let devicesDir = repoDir.appendingPathComponent("devices")
        guard let files = try? FileManager.default.contentsOfDirectory(at: devicesDir, includingPropertiesForKeys: nil) else {
            return []
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? dec.decode(DeviceSnapshot.self, from: $0) }
            .sorted { $0.syncedAt > $1.syncedAt }
    }
}
