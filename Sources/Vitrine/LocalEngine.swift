import Foundation
import Observation

// MARK: - Models

struct LocalModel: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var sizeBytes: Int
    var paramSize: String

    var sizeLabel: String {
        let gb = Double(sizeBytes) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1fGB", gb)
                       : String(format: "%.0fMB", Double(sizeBytes) / 1_048_576)
    }
}

struct PullProgress: Equatable {
    var status: String
    var fraction: Double     // 0...1, or -1 when indeterminate
}

// MARK: - Ollama (llama.cpp runtime with native model pulling)

/// Local inference via Ollama — the standard llama.cpp runtime on macOS.
/// Mirrors hindsight's local-engine capabilities (list local models, pull with progress,
/// run) without bundling a binary, by driving Ollama's HTTP API + CLI.
enum Ollama {
    static let base = "http://localhost:11434"
    static var openAIEndpoint: String { base + "/v1" }

    static var cliPath: String? {
        for p in ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama", NSHomeDirectory() + "/.local/bin/ollama"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return CLI.which("ollama")
    }

    /// Is the server reachable right now?
    static func serverUp() async -> Bool {
        var req = URLRequest(url: URL(string: base + "/api/version")!)
        req.timeoutInterval = 2.5
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200..<500).contains(http.statusCode)
    }

    static func listModels() async throws -> [LocalModel] {
        var req = URLRequest(url: URL(string: base + "/api/tags")!)
        req.timeoutInterval = 6
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.network("Ollama 未响应（localhost:11434）")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["models"] as? [[String: Any]] else { return [] }
        return arr.map { m in
            let details = m["details"] as? [String: Any]
            return LocalModel(
                name: (m["name"] as? String) ?? "?",
                sizeBytes: (m["size"] as? Int) ?? 0,
                paramSize: (details?["parameter_size"] as? String) ?? "")
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Start `ollama serve` detached. Returns immediately; caller re-checks serverUp().
    static func startServer() -> Bool {
        guard let cli = cliPath else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = ["serve"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); return true } catch { return false }
    }

    /// Pull a model, streaming NDJSON progress. Cancels when the Task is cancelled.
    static func pull(_ name: String, onProgress: @escaping @Sendable (PullProgress) -> Void) async throws {
        guard let url = URL(string: base + "/api/pull") else { throw AIError.notConfigured("地址非法") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "stream": true])
        req.timeoutInterval = 3600

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.network("拉取失败：服务返回错误（模型名是否正确？）")
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            if let err = obj["error"] as? String { throw AIError.network(err) }
            let status = (obj["status"] as? String) ?? ""
            var frac = -1.0
            if let completed = obj["completed"] as? Int, let total = obj["total"] as? Int, total > 0 {
                frac = Double(completed) / Double(total)
            }
            onProgress(PullProgress(status: status, fraction: frac))
            if status == "success" { break }
        }
    }
}

// MARK: - llama.cpp llama-server supervisor

/// Spawns a `llama-server` process for a chosen GGUF (hindsight-style local engine, minimal).
/// Chat then flows through the OpenAI-compatible endpoint it exposes.
@Observable
final class LlamaServer {
    enum State: Equatable { case stopped, starting, running(port: Int), failed(String) }
    var state: State = .stopped
    @ObservationIgnored private var process: Process?

    var binaryPath: String? {
        for p in ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return CLI.which("llama-server")
    }
    var installed: Bool { binaryPath != nil }

    func endpoint(port: Int) -> String { "http://127.0.0.1:\(port)/v1" }

    /// Spawn llama-server -m <gguf> --port <port>; poll /health until ready.
    @MainActor
    func start(ggufPath: String, port: Int = 8080, ctxSize: Int = 8192) {
        guard let bin = binaryPath else { state = .failed("未找到 llama-server"); return }
        guard FileManager.default.fileExists(atPath: (ggufPath as NSString).expandingTildeInPath) else {
            state = .failed("GGUF 文件不存在"); return
        }
        stop()
        state = .starting
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["-m", (ggufPath as NSString).expandingTildeInPath,
                       "--port", "\(port)", "--ctx-size", "\(ctxSize)", "--jinja"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { state = .failed("启动失败：\(error.localizedDescription)"); return }
        process = p

        Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(800))
                if await Self.healthy(port: port) { state = .running(port: port); return }
                if !p.isRunning { state = .failed("llama-server 提前退出（检查模型/显存）"); return }
            }
            state = .failed("启动超时")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        state = .stopped
    }

    private static func healthy(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: url); req.timeoutInterval = 2
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}

// MARK: - Local engine facade (observable, for the AI settings UI)

@Observable
final class LocalEngineModel {
    var ollamaUp = false
    var ollamaModels: [LocalModel] = []
    var checking = false

    // Pull state
    var pulling = false
    var pullName = ""
    var pullProgress: PullProgress?
    @ObservationIgnored var pullTask: Task<Void, Never>?

    let llama = LlamaServer()

    var ollamaInstalled: Bool { Ollama.cliPath != nil }

    @MainActor
    func refresh() async {
        checking = true
        ollamaUp = await Ollama.serverUp()
        if ollamaUp {
            ollamaModels = (try? await Ollama.listModels()) ?? []
        } else {
            ollamaModels = []
        }
        checking = false
    }

    @MainActor
    func startOllama() async {
        _ = Ollama.startServer()
        // Give it a moment, then re-probe a few times.
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(700))
            if await Ollama.serverUp() { break }
        }
        await refresh()
    }

    @MainActor
    func startPull(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !pulling else { return }
        pulling = true
        pullName = trimmed
        pullProgress = PullProgress(status: "开始拉取…", fraction: -1)
        let model = self
        pullTask = Task {
            do {
                try await Ollama.pull(trimmed) { p in
                    Task { @MainActor in model.pullProgress = p }
                }
                await MainActor.run {
                    model.pullProgress = PullProgress(status: "完成", fraction: 1)
                    model.pulling = false
                }
                await model.refresh()
            } catch is CancellationError {
                await MainActor.run { model.pulling = false; model.pullProgress = nil }
            } catch {
                await MainActor.run {
                    model.pullProgress = PullProgress(status: "失败：\(error.localizedDescription)", fraction: -1)
                    model.pulling = false
                }
            }
        }
    }

    @MainActor
    func cancelPull() {
        pullTask?.cancel()
        pulling = false
        pullProgress = nil
    }
}
