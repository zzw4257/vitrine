import Foundation
import Observation

// MARK: - Provider presets (mirrors hindsight's ExternalApiTab)

struct AIProviderPreset: Identifiable, Hashable {
    var id: String
    var name: String
    var baseURL: String
    var modelHint: String
}

enum AIProviders {
    /// `localClaude` is Vitrine-specific: shells out to the `claude` CLI instead of HTTP.
    static let localClaude = AIProviderPreset(
        id: "local-claude", name: "本地 Claude CLI", baseURL: "", modelHint: "claude-haiku-4-5-20251001")

    static let ollama = AIProviderPreset(
        id: "ollama", name: "Ollama 本地", baseURL: "http://localhost:11434/v1", modelHint: "qwen2.5:7b")
    static let llamacpp = AIProviderPreset(
        id: "llamacpp", name: "本地 llama.cpp", baseURL: "http://127.0.0.1:8080/v1", modelHint: "local-gguf")

    static let external: [AIProviderPreset] = [
        ollama, llamacpp,
        .init(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", modelHint: "gpt-4o-mini"),
        .init(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", modelHint: "deepseek-chat"),
        .init(id: "kimi", name: "Kimi (Moonshot)", baseURL: "https://api.moonshot.ai/v1", modelHint: "kimi-k2.6"),
        .init(id: "kimi-cn", name: "Kimi 国内", baseURL: "https://api.moonshot.cn/v1", modelHint: "kimi-k2.6"),
        .init(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", modelHint: "anthropic/claude-3.5-sonnet"),
        .init(id: "together", name: "Together", baseURL: "https://api.together.xyz/v1", modelHint: "meta-llama/Llama-3.3-70B-Instruct-Turbo"),
        .init(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", modelHint: "llama-3.3-70b-versatile"),
        .init(id: "custom", name: "自定义", baseURL: "", modelHint: ""),
    ]

    static let all: [AIProviderPreset] = [localClaude] + external
    static func by(_ id: String) -> AIProviderPreset { all.first { $0.id == id } ?? localClaude }

    static let localIDs: Set<String> = ["ollama", "llamacpp"]
}

// MARK: - Settings

@Observable
final class AISettings {
    var providerID: String { didSet { persist() } }
    var endpoint: String { didSet { persist() } }
    var apiKey: String { didSet { persist() } }
    var model: String { didSet { persist() } }
    /// Models discovered via GET /models — populated by "拉取模型".
    var availableModels: [String] = []

    // llama.cpp local-server config
    var ggufPath: String { didSet { persist() } }
    var llamaPort: Int { didSet { persist() } }

    var provider: AIProviderPreset { AIProviders.by(providerID) }
    var isLocalClaude: Bool { providerID == AIProviders.localClaude.id }
    var isLocalEngine: Bool { AIProviders.localIDs.contains(providerID) }
    var configured: Bool {
        isLocalClaude ? true : (!endpoint.trimmed.isEmpty && !model.trimmed.isEmpty)
    }

    init() {
        let d = UserDefaults.standard
        providerID = d.string(forKey: "vitrine.ai.provider") ?? AIProviders.localClaude.id
        endpoint = d.string(forKey: "vitrine.ai.endpoint") ?? ""
        model = d.string(forKey: "vitrine.ai.model") ?? ""
        ggufPath = d.string(forKey: "vitrine.ai.ggufPath") ?? ""
        llamaPort = (d.object(forKey: "vitrine.ai.llamaPort") as? Int) ?? 8080
        // Convenience: seed the key from the environment / codex auth on first run, never overwrite.
        if let saved = d.string(forKey: "vitrine.ai.apiKey") {
            apiKey = saved
        } else {
            apiKey = AISettings.seedKey()
        }
    }

    private static func seedKey() -> String {
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty { return env }
        let authPath = NSHomeDirectory() + "/.codex/auth.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: authPath)),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let k = obj["OPENAI_API_KEY"] as? String, !k.isEmpty {
            return k
        }
        return ""
    }

    /// Apply a provider preset: fill base URL, keep any model the user already typed.
    func applyProvider(_ p: AIProviderPreset) {
        providerID = p.id
        if p.id != "custom" && p.id != AIProviders.localClaude.id {
            endpoint = p.baseURL
        }
        availableModels = []
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(providerID, forKey: "vitrine.ai.provider")
        d.set(endpoint, forKey: "vitrine.ai.endpoint")
        d.set(apiKey, forKey: "vitrine.ai.apiKey")
        d.set(model, forKey: "vitrine.ai.model")
        d.set(ggufPath, forKey: "vitrine.ai.ggufPath")
        d.set(llamaPort, forKey: "vitrine.ai.llamaPort")
    }

    func snapshot() -> AIConfig {
        AIConfig(providerID: providerID, endpoint: endpoint.trimmed,
                 apiKey: apiKey.trimmed, model: model.trimmed)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Client

/// Immutable snapshot of settings safe to pass to a detached task.
struct AIConfig: Sendable {
    var providerID: String
    var endpoint: String
    var apiKey: String
    var model: String
    var isLocalClaude: Bool { providerID == "local-claude" }
}

enum AIError: LocalizedError {
    case notConfigured(String)
    case http(Int, String)
    case network(String)
    case decode(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .notConfigured(let m): m
        case .http(let c, let m): "服务返回 \(c)：\(m)"
        case .network(let m): m
        case .decode(let m): "响应解析失败：\(m)"
        case .empty: "模型返回了空内容"
        }
    }
}

enum AIClient {
    /// List available model IDs via `GET {endpoint}/models` (hindsight's connectivity probe).
    static func listModels(_ cfg: AIConfig) async throws -> [String] {
        let base = cfg.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        guard !base.isEmpty else { throw AIError.notConfigured("服务地址为空") }
        guard let url = URL(string: base + "/models") else { throw AIError.notConfigured("地址格式非法") }
        var req = URLRequest(url: url)
        if !cfg.apiKey.isEmpty { req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization") }
        req.timeoutInterval = 12

        let (data, resp) = try await send(req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.network("无 HTTP 响应") }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(http.statusCode, preview(data))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["data"] as? [[String: Any]] else {
            throw AIError.decode("不是 OpenAI 兼容的 /models 格式")
        }
        return arr.compactMap { $0["id"] as? String }.sorted()
    }

    /// One-shot chat completion. For localClaude, shells out to `claude -p`.
    static func chat(_ cfg: AIConfig, system: String, user: String,
                     maxTokens: Int = 2000, timeout: TimeInterval = 180) async throws -> String {
        if cfg.isLocalClaude {
            let claude = CLI.detectTools().first { $0.name == "claude" }?.path
            guard let claude else { throw AIError.notConfigured("未检测到 claude CLI") }
            let prompt = system.isEmpty ? user : system + "\n\n" + user
            let model = cfg.model.isEmpty ? "claude-haiku-4-5-20251001" : cfg.model
            return try await CLI.runClaude(prompt, claudePath: claude, model: model, timeout: timeout)
        }

        let base = cfg.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        guard !base.isEmpty, !cfg.model.isEmpty else { throw AIError.notConfigured("请先在设置里配置 API") }
        guard let url = URL(string: base + "/chat/completions") else { throw AIError.notConfigured("地址格式非法") }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !cfg.apiKey.isEmpty { req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization") }
        req.timeoutInterval = timeout
        let body: [String: Any] = [
            "model": cfg.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "stream": false,
            "temperature": 0.4,
            "max_tokens": maxTokens,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await send(req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.network("无 HTTP 响应") }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(http.statusCode, preview(data))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw AIError.decode(preview(data))
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.empty }
        return trimmed
    }

    /// Two-step test: connectivity (GET /models) then a 1-token chat to validate the model ID.
    static func test(_ cfg: AIConfig) async -> (connOK: Bool, connMsg: String, chatOK: Bool, chatMsg: String) {
        if cfg.isLocalClaude {
            let ok = CLI.detectTools().contains { $0.name == "claude" }
            return (ok, ok ? "已检测到 claude CLI" : "未检测到 claude", ok, ok ? "可用" : "不可用")
        }
        var connOK = false, connMsg = "", chatOK = false, chatMsg = ""
        do {
            let models = try await listModels(cfg)
            connOK = true
            connMsg = "连通，可见 \(models.count) 个模型"
        } catch {
            return (false, error.localizedDescription, false, "")
        }
        do {
            _ = try await chat(cfg, system: "", user: "ping", maxTokens: 1, timeout: 30)
            chatOK = true; chatMsg = "模型可用"
        } catch let e as AIError {
            if case .empty = e { chatOK = true; chatMsg = "模型可用" }
            else { chatMsg = e.localizedDescription }
        } catch {
            chatMsg = error.localizedDescription
        }
        return (connOK, connMsg, chatOK, chatMsg)
    }

    // MARK: helpers

    private static func send(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await URLSession.shared.data(for: req) }
        catch { throw AIError.network(friendly(error)) }
    }

    private static func friendly(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut: return "请求超时"
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
                return "连接失败（确认服务是否启动、地址是否正确）"
            case NSURLErrorNotConnectedToInternet: return "无网络连接"
            default: return ns.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func preview(_ data: Data) -> String {
        String(String(data: data, encoding: .utf8)?.prefix(160) ?? "")
    }
}
