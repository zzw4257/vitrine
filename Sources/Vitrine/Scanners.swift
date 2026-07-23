import Foundation
import CryptoKit
import SQLite3

// MARK: - Shared parsing helpers

enum JSONL {
    static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFrac.date(from: s) ?? iso.date(from: s)
    }

    /// Stream a file line-by-line without loading it all at once.
    static func forEachLine(of url: URL, _ body: ([String: Any]) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        var buffer = Data()
        let newline = UInt8(ascii: "\n")
        while true {
            guard let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            buffer.append(chunk)
            while let idx = buffer.firstIndex(of: newline) {
                let lineData = buffer.subdata(in: buffer.startIndex..<idx)
                buffer.removeSubrange(buffer.startIndex...idx)
                if lineData.isEmpty { continue }
                if let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any] {
                    body(obj)
                }
            }
        }
        if !buffer.isEmpty, let obj = (try? JSONSerialization.jsonObject(with: buffer)) as? [String: Any] {
            body(obj)
        }
    }

    /// Injected / system-generated prefixes that are NOT real user intent and should never
    /// surface as a session title or summary text.
    private static let injectedPrefixes = [
        "<", "Caveat:", "[Request interrupted", "# AGENTS.md instructions",
        "Generate metadata for", "You are ", "You're ", "请先阅读 .vitrine-briefing",
        "<system-reminder>", "This session is being continued", "Please continue",
        "# CLAUDE.md", "The user opened", "Analyzing the codebase",
        "# Context from", "## Active file", "<ide_", "# Files mentioned",
        "[$",
    ]
    private static let injectedContains = [
        "instructions for /", "based on the user prompt", "AUTONOMY DIRECTIVE",
        "<command-name>", "<command-message>", "<local-command",
        "Files mentioned by the user",
    ]

    static func cleanPrompt(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        for p in injectedPrefixes where t.hasPrefix(p) { return nil }
        let head = String(t.prefix(80))
        for c in injectedContains where head.contains(c) { return nil }
        return String(t.prefix(400))
    }
}

private let maxPrompts = 60
private let maxCommands = 300
private let maxFiles = 200

// MARK: - Claude Code (~/.claude/projects/**/*.jsonl)

enum ClaudeScanner {
    static func discover() -> [URL] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        return dirs.flatMap { dir -> [URL] in
            (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "jsonl" } ?? []
        }
    }

    static func scan(_ url: URL) -> SessionRecord? {
        var cwd: String?, branch: String?, cliVersion: String?
        var start: Date?, end: Date?
        var userN = 0, asstN = 0, inTok = 0, outTok = 0, totalTok = 0
        var models = Set<String>(), tools: [String: Int] = [:]
        var cmds: [String] = [], files = Set<String>(), prompts: [String] = []
        var title: String?
        var cacheReadTok = 0, cacheCreationTok = 0

        JSONL.forEachLine(of: url) { obj in
            guard let type = obj["type"] as? String else { return }
            guard type == "user" || type == "assistant" else { return }
            if let ts = JSONL.date(obj["timestamp"] as? String) {
                if start == nil || ts < start! { start = ts }
                if end == nil || ts > end! { end = ts }
            }
            if cwd == nil { cwd = obj["cwd"] as? String }
            if branch == nil { branch = obj["gitBranch"] as? String }
            if cliVersion == nil { cliVersion = obj["version"] as? String }
            let sidechain = obj["isSidechain"] as? Bool ?? false
            let meta = obj["isMeta"] as? Bool ?? false
            guard let msg = obj["message"] as? [String: Any] else { return }

            if type == "user" {
                var texts: [String] = []
                if let s = msg["content"] as? String {
                    texts.append(s)
                } else if let blocks = msg["content"] as? [[String: Any]] {
                    for b in blocks where (b["type"] as? String) == "text" {
                        if let t = b["text"] as? String { texts.append(t) }
                    }
                }
                let cleaned = texts.compactMap(JSONL.cleanPrompt)
                guard !cleaned.isEmpty else { return }
                if meta { return }
                userN += 1
                if !sidechain, prompts.count < maxPrompts { prompts.append(contentsOf: cleaned) }
                if title == nil, !sidechain { title = cleaned.first }
            } else {
                asstN += 1
                if let m = msg["model"] as? String { models.insert(m) }
                if let usage = msg["usage"] as? [String: Any] {
                    let i = (usage["input_tokens"] as? Int) ?? 0
                    let o = (usage["output_tokens"] as? Int) ?? 0
                    let cr = (usage["cache_read_input_tokens"] as? Int) ?? 0
                    let cc = (usage["cache_creation_input_tokens"] as? Int) ?? 0
                    inTok += i
                    outTok += o
                    totalTok += i + o + cr + cc
                    cacheReadTok += cr
                    cacheCreationTok += cc
                }
                if let blocks = msg["content"] as? [[String: Any]] {
                    for b in blocks where (b["type"] as? String) == "tool_use" {
                        let name = (b["name"] as? String) ?? "tool"
                        tools[name, default: 0] += 1
                        let input = b["input"] as? [String: Any]
                        if name == "Bash", let c = input?["command"] as? String, cmds.count < maxCommands {
                            cmds.append(String(c.prefix(200)))
                        }
                        if let fp = input?["file_path"] as? String, files.count < maxFiles {
                            files.insert(fp)
                        }
                    }
                }
            }
        }

        guard userN + asstN > 0, let s = start, let e = end else { return nil }
        let project = cwd ?? decodeProjectDir(url.deletingLastPathComponent().lastPathComponent)
        return SessionRecord(
            id: "claude-" + url.deletingPathExtension().lastPathComponent,
            agent: .claude, filePath: url.path, projectPath: normalize(project),
            gitBranch: branch,
            title: String((title ?? "（无标题会话）").prefix(90)),
            startedAt: s, endedAt: e,
            userMessages: userN, assistantMessages: asstN,
            inputTokens: inTok, outputTokens: outTok,
            totalTokens: max(totalTok, inTok + outTok), tokensEstimated: false,
            cacheReadTokens: cacheReadTok, cacheCreationTokens: cacheCreationTok,
            models: models.sorted(), toolCounts: tools,
            bashCommands: cmds, filesTouched: Array(files).sorted(),
            userPrompts: prompts, isSubagent: false, cliVersion: cliVersion, summary: nil)
    }

    /// "-Users-zzw4257-Documents-Foo" → "/Users/zzw4257/Documents/Foo" (best effort; cwd is preferred).
    static func decodeProjectDir(_ encoded: String) -> String {
        encoded.replacingOccurrences(of: "-", with: "/")
    }
}

// MARK: - Codex (~/.codex/sessions/**/rollout-*.jsonl)

enum CodexScanner {
    static func discover() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var out: [URL] = []
        for sub in [".codex/sessions", ".codex/archived_sessions"] {
            let root = home.appendingPathComponent(sub)
            guard let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil) else { continue }
            for case let u as URL in e where u.pathExtension == "jsonl" && u.lastPathComponent.hasPrefix("rollout-") {
                out.append(u)
            }
        }
        return out
    }

    static func scan(_ url: URL) -> SessionRecord? {
        var cwd: String?, cliVersion: String?, originator: String?
        var isSubagent = false, nickname: String?
        var start: Date?, end: Date?
        var userN = 0, asstN = 0
        var models = Set<String>(), tools: [String: Int] = [:]
        var cmds: [String] = [], files = Set<String>(), prompts: [String] = []
        var eventPrompts: [String] = []
        var title: String?
        var asstChars = 0
        var tokIn: Int?, tokOut: Int?, tokTotal: Int?, tokCached: Int?

        JSONL.forEachLine(of: url) { obj in
            if let ts = JSONL.date(obj["timestamp"] as? String) {
                if start == nil || ts < start! { start = ts }
                if end == nil || ts > end! { end = ts }
            }
            guard let type = obj["type"] as? String,
                  let payload = obj["payload"] as? [String: Any] else { return }

            switch type {
            case "session_meta":
                cwd = (payload["cwd"] as? String) ?? cwd
                cliVersion = (payload["cli_version"] as? String) ?? cliVersion
                originator = (payload["originator"] as? String) ?? originator
                nickname = (payload["agent_nickname"] as? String) ?? nickname
                if (payload["thread_source"] as? String) == "subagent" { isSubagent = true }
                if let src = payload["source"] as? [String: Any], src["subagent"] != nil { isSubagent = true }
            case "turn_context":
                if cwd == nil { cwd = payload["cwd"] as? String }
                if let m = payload["model"] as? String { models.insert(m) }
            case "response_item":
                switch payload["type"] as? String {
                case "message":
                    let role = payload["role"] as? String
                    let contents = payload["content"] as? [[String: Any]] ?? []
                    if role == "user" {
                        let texts = contents
                            .filter { ($0["type"] as? String) == "input_text" }
                            .compactMap { $0["text"] as? String }
                            .compactMap(JSONL.cleanPrompt)
                        guard !texts.isEmpty else { return }
                        userN += 1
                        if prompts.count < maxPrompts { prompts.append(contentsOf: texts) }
                        if title == nil { title = texts.first }
                    } else if role == "assistant" {
                        asstN += 1
                        for c in contents where (c["type"] as? String) == "output_text" {
                            asstChars += (c["text"] as? String)?.count ?? 0
                        }
                    }
                case "function_call":
                    let name = (payload["name"] as? String) ?? "tool"
                    tools[name, default: 0] += 1
                    if let argStr = payload["arguments"] as? String,
                       let argData = argStr.data(using: .utf8),
                       let args = (try? JSONSerialization.jsonObject(with: argData)) as? [String: Any] {
                        if let c = args["command"] as? String, cmds.count < maxCommands {
                            cmds.append(String(c.prefix(200)))
                        } else if let arr = args["command"] as? [String], cmds.count < maxCommands {
                            cmds.append(String(arr.joined(separator: " ").prefix(200)))
                        }
                        for k in ["file_path", "path"] {
                            if let fp = args[k] as? String, files.count < maxFiles { files.insert(fp) }
                        }
                    }
                case "local_shell_call":
                    tools["shell", default: 0] += 1
                    if let action = payload["action"] as? [String: Any],
                       let arr = action["command"] as? [String], cmds.count < maxCommands {
                        cmds.append(String(arr.joined(separator: " ").prefix(200)))
                    }
                case "custom_tool_call":
                    tools[(payload["name"] as? String) ?? "tool", default: 0] += 1
                default: break
                }
            case "event_msg":
                switch payload["type"] as? String {
                case "user_message":
                    if let t = (payload["message"] as? String).flatMap(JSONL.cleanPrompt),
                       eventPrompts.count < maxPrompts {
                        eventPrompts.append(t)
                    }
                case "token_count":
                    let info = (payload["info"] as? [String: Any]) ?? payload
                    if let usage = info["total_token_usage"] as? [String: Any] {
                        // total_token_usage is cumulative — keep the largest seen.
                        let i = usage["input_tokens"] as? Int ?? 0
                        let o = usage["output_tokens"] as? Int ?? 0
                        // `cached_input_tokens` is a SUBSET of input_tokens (OpenAI's discounted-
                        // rate re-read), not an extra read the way Anthropic's cache fields are —
                        // adding it on top double-counted total throughput for every Codex session.
                        let cached = usage["cached_input_tokens"] as? Int ?? 0
                        tokIn = max(tokIn ?? 0, i)
                        tokOut = max(tokOut ?? 0, o)
                        tokTotal = max(tokTotal ?? 0, i + o)
                        tokCached = max(tokCached ?? 0, cached)
                    }
                default: break
                }
            default: break
            }
        }

        if prompts.isEmpty { prompts = eventPrompts; userN = max(userN, eventPrompts.count) }
        if title == nil { title = eventPrompts.first }
        guard userN + asstN > 0, let s = start, let e = end, let dir = cwd else { return nil }

        var t = title ?? "（无标题会话）"
        if let n = nickname { t = "[\(n)] " + t }
        return SessionRecord(
            id: "codex-" + url.deletingPathExtension().lastPathComponent,
            agent: .codex, filePath: url.path, projectPath: normalize(dir),
            gitBranch: nil,
            title: String(t.prefix(90)),
            startedAt: s, endedAt: e,
            userMessages: userN, assistantMessages: asstN,
            inputTokens: tokIn ?? 0,
            outputTokens: tokOut ?? asstChars / 4,
            totalTokens: tokTotal ?? ((tokIn ?? 0) + (tokOut ?? asstChars / 4)),
            tokensEstimated: tokOut == nil,
            cacheReadTokens: tokCached,
            models: models.sorted(), toolCounts: tools,
            bashCommands: cmds, filesTouched: Array(files).sorted(),
            userPrompts: prompts, isSubagent: isSubagent,
            cliVersion: (originator.map { "\($0) " } ?? "") + (cliVersion ?? ""),
            summary: nil)
    }
}

// MARK: - opencode (~/.local/share/opencode/storage)

enum OpencodeScanner {
    static func scanAll() -> [SessionRecord] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/storage")
        let sessionRoot = root.appendingPathComponent("session")
        guard let projDirs = try? FileManager.default.contentsOfDirectory(
            at: sessionRoot, includingPropertiesForKeys: nil) else { return [] }

        var out: [SessionRecord] = []
        for projDir in projDirs {
            guard let sessionFiles = try? FileManager.default.contentsOfDirectory(
                at: projDir, includingPropertiesForKeys: nil) else { continue }
            for f in sessionFiles where f.pathExtension == "json" {
                guard let data = try? Data(contentsOf: f),
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let id = obj["id"] as? String,
                      let dir = obj["directory"] as? String,
                      let time = obj["time"] as? [String: Any],
                      let created = time["created"] as? Double else { continue }
                let updated = (time["updated"] as? Double) ?? created
                let msgDir = root.appendingPathComponent("message/\(id)")
                let msgCount = (try? FileManager.default.contentsOfDirectory(atPath: msgDir.path).count) ?? 0
                guard msgCount > 0 else { continue }
                out.append(SessionRecord(
                    id: "opencode-\(id)",
                    agent: .opencode, filePath: f.path, projectPath: normalize(dir),
                    gitBranch: nil,
                    title: String(((obj["title"] as? String) ?? "（无标题会话）").prefix(90)),
                    startedAt: Date(timeIntervalSince1970: created / 1000),
                    endedAt: Date(timeIntervalSince1970: updated / 1000),
                    userMessages: msgCount / 2, assistantMessages: msgCount / 2,
                    inputTokens: 0, outputTokens: 0, totalTokens: 0, tokensEstimated: true,
                    models: [], toolCounts: [:], bashCommands: [], filesTouched: [],
                    userPrompts: [], isSubagent: (obj["parentID"] as? String) != nil,
                    cliVersion: obj["version"] as? String, summary: nil))
            }
        }
        return out
    }
}

// MARK: - Gemini CLI (~/.gemini/tmp/<sha256(projectPath)>/chats/session-*.json)

enum GeminiScanner {
    /// Gemini names each project dir by the SHA-256 hex of its absolute cwd, so we resolve
    /// projects by hashing every path the other scanners already surfaced. Unmatched hashes
    /// fall back to a stable, readable per-hash bucket. Few files → plain batch scan, no cache.
    static func scanAll(knownPaths: [String]) -> [SessionRecord] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/tmp")
        guard let hashDirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return [] }

        var hashToPath: [String: String] = [:]
        for p in Set(knownPaths) { hashToPath[sha256Hex(p)] = p }

        var out: [SessionRecord] = []
        for dir in hashDirs {
            let hash = dir.lastPathComponent
            let chatDir = dir.appendingPathComponent("chats")
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: chatDir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "json" {
                if let rec = scan(f, hash: hash, resolvedPath: hashToPath[hash]) { out.append(rec) }
            }
        }
        return out
    }

    private static func scan(_ url: URL, hash: String, resolvedPath: String?) -> SessionRecord? {
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let messages = obj["messages"] as? [[String: Any]] else { return nil }

        let sid = (obj["sessionId"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let start = JSONL.date(obj["startTime"] as? String)
        let end = JSONL.date(obj["lastUpdated"] as? String)

        var userN = 0, asstN = 0, inTok = 0, outTok = 0, totalTok = 0
        var models = Set<String>()
        var prompts: [String] = []
        var title: String?

        for m in messages {
            switch m["type"] as? String {
            case "user":
                guard let c = (m["content"] as? String).flatMap(JSONL.cleanPrompt) else { continue }
                userN += 1
                if prompts.count < maxPrompts { prompts.append(c) }
                if title == nil { title = c }
            case "gemini":
                asstN += 1
                if let mdl = m["model"] as? String { models.insert(mdl) }
                if let t = m["tokens"] as? [String: Any] {
                    inTok += (t["input"] as? Int) ?? 0
                    outTok += (t["output"] as? Int) ?? 0
                    totalTok += (t["total"] as? Int) ?? 0
                }
            default: break
            }
        }

        guard userN + asstN > 0, let s = start, let e = end else { return nil }
        let project = resolvedPath ?? "Gemini 项目 " + String(hash.prefix(8))
        return SessionRecord(
            id: "gemini-" + sid,
            agent: .gemini, filePath: url.path, projectPath: normalize(project),
            gitBranch: nil,
            title: String((title ?? "（无标题会话）").prefix(90)),
            startedAt: s, endedAt: e,
            userMessages: userN, assistantMessages: asstN,
            inputTokens: inTok, outputTokens: outTok,
            totalTokens: max(totalTok, inTok + outTok), tokensEstimated: false,
            models: models.sorted(), toolCounts: [:],
            bashCommands: [], filesTouched: [],
            userPrompts: prompts, isSubagent: false, cliVersion: nil, summary: nil)
    }

    static func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Cursor (~/.cursor/ai-tracking/ai-code-tracking.db)

/// Cursor keeps a clean relational store: `conversation_summaries` (title/tldr/overview/model/mode)
/// plus `ai_code_hashes` (per-edit model/file/conversation/timestamp). We read it read-only.
/// The transcript bodies themselves aren't here — this is Cursor's own summary layer — so a
/// record is an accurate "what Cursor did" card rather than a full turn-by-turn log.
enum CursorScanner {
    static func scanAll(knownPaths: [String]) -> [SessionRecord] {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/ai-tracking/ai-code-tracking.db").path
        guard FileManager.default.fileExists(atPath: path) else { return [] }

        var db: OpaquePointer?
        // Read-only + immutable so a running Cursor holding a write lock can't block us.
        guard sqlite3_open_v2("file:\(path)?immutable=1", &db,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db); return []
        }
        defer { sqlite3_close(db) }

        // Per-conversation edit facts: files touched, model, activity window.
        struct Edits { var files = Set<String>(); var models = Set<String>(); var lo = 0.0; var hi = 0.0 }
        var edits: [String: Edits] = [:]
        query(db, "SELECT conversationId, fileName, model, timestamp FROM ai_code_hashes") { s in
            guard let cid = text(s, 0) else { return }
            var e = edits[cid] ?? Edits()
            if let f = text(s, 1), !f.isEmpty { e.files.insert(f) }
            if let m = text(s, 2), !m.isEmpty { e.models.insert(m) }
            let t = epochSeconds(sqlite3_column_double(s, 3))
            if t > 0 { e.lo = e.lo == 0 ? t : min(e.lo, t); e.hi = max(e.hi, t) }
            edits[cid] = e
        }

        var out: [SessionRecord] = []
        query(db, """
            SELECT conversationId, title, tldr, overview, model, mode, updatedAt \
            FROM conversation_summaries ORDER BY updatedAt DESC
            """) { s in
            guard let cid = text(s, 0) else { return }
            let title = text(s, 1) ?? "（无标题会话）"
            let tldr = text(s, 2), overview = text(s, 3)
            let model = text(s, 4) ?? ""
            let mode = text(s, 5)
            let updated = epochSeconds(sqlite3_column_double(s, 6))

            let e = edits[cid]
            let lo = (e?.lo ?? 0) > 0 ? e!.lo : updated
            let hi = (e?.hi ?? 0) > 0 ? e!.hi : updated
            guard lo > 0 else { return }

            var models = e?.models ?? []
            if !model.isEmpty { models.insert(model) }
            let files = Array(e?.files ?? []).sorted()
            let project = resolveCursorProject(files: files, knownPaths: knownPaths)
            let summary = [tldr, overview].compactMap { $0 }.first { !$0.isEmpty }

            out.append(SessionRecord(
                id: "cursor-" + cid,
                agent: .cursor, filePath: path, projectPath: normalize(project),
                gitBranch: nil,
                title: String(((mode.map { "[\($0)] " } ?? "") + title).prefix(90)),
                startedAt: Date(timeIntervalSince1970: lo),
                endedAt: Date(timeIntervalSince1970: hi),
                userMessages: 1, assistantMessages: 1,
                inputTokens: 0, outputTokens: 0, totalTokens: 0, tokensEstimated: true,
                models: models.sorted(), toolCounts: [:],
                bashCommands: [], filesTouched: files.map { ($0 as NSString).lastPathComponent },
                userPrompts: [], isSubagent: false, cliVersion: "cursor",
                summary: summary))
        }
        return out
    }

    /// Prefer a known project whose path contains one of the edited files; else a "Cursor" bucket.
    private static func resolveCursorProject(files: [String], knownPaths: [String]) -> String {
        for f in files where f.hasPrefix("/") {
            let dir = (f as NSString).deletingLastPathComponent
            if let hit = knownPaths.first(where: { dir == $0 || dir.hasPrefix($0 + "/") || $0.hasPrefix(dir) }) {
                return hit
            }
        }
        // Fall back to the first file's directory if it's absolute, else a single Cursor bucket.
        if let abs = files.first(where: { $0.hasPrefix("/") }) {
            return (abs as NSString).deletingLastPathComponent
        }
        return "Cursor"
    }

    private static func query(_ db: OpaquePointer?, _ sql: String, _ row: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        sqlite3_column_text(stmt, col).map { String(cString: $0) }
    }

    /// Cursor timestamps are epoch milliseconds; normalize to seconds. 0 stays 0.
    private static func epochSeconds(_ v: Double) -> Double {
        v > 1_000_000_000_000 ? v / 1000 : v
    }
}

// MARK: - Windsurf / Cascade (~/.codeium/windsurf/code_tracker)

/// Windsurf's Cascade conversation store (`cascade/*.pb`, `memories/*.pb`) is ENCRYPTED at rest
/// (verified: ~8 bits/byte entropy, no transcript recoverable). The one readable signal is the
/// code tracker: per-workspace copies of the files Cascade touched. So a record here is an honest
/// activity footprint — which project, which files, active when — not a transcript.
enum WindsurfScanner {
    static func scanAll(knownPaths: [String]) -> [SessionRecord] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codeium/windsurf/code_tracker/active")
        guard let workspaces = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return [] }

        var out: [SessionRecord] = []
        for ws in workspaces {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: ws.path, isDirectory: &isDir), isDir.boolValue else { continue }

            // Collect touched files (recursively) with their mtimes.
            var files: [String] = []
            var lo = Date.distantFuture, hi = Date.distantPast
            if let e = FileManager.default.enumerator(at: ws, includingPropertiesForKeys: [.contentModificationDateKey]) {
                for case let f as URL in e {
                    guard (try? f.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                    files.append(cleanFileName(f.lastPathComponent))
                    if let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                        lo = min(lo, m); hi = max(hi, m)
                    }
                }
            }
            guard !files.isEmpty, lo <= hi else { continue }

            let name = projectName(fromWorkspace: ws.lastPathComponent)
            let project = knownPaths.first { ($0 as NSString).lastPathComponent == name } ?? name
            let shown = Array(Set(files)).sorted()
            let head = shown.prefix(3).joined(separator: "、")

            out.append(SessionRecord(
                id: "windsurf-" + ws.lastPathComponent,
                agent: .windsurf, filePath: ws.path, projectPath: normalize(project),
                gitBranch: nil,
                title: String("Windsurf · \(shown.count) 个文件：\(head)".prefix(90)),
                startedAt: lo, endedAt: hi,
                userMessages: 1, assistantMessages: 1,
                inputTokens: 0, outputTokens: 0, totalTokens: 0, tokensEstimated: true,
                models: [], toolCounts: [:],
                bashCommands: [], filesTouched: shown,
                userPrompts: [], isSubagent: false, cliVersion: "windsurf",
                summary: "Windsurf/Cascade 会话（对话转录在本地加密存储，此处仅还原其触碰过的文件足迹）。"))
        }
        return out
    }

    /// "cve_genesis_17d24e…<40 hex git sha>" → "cve_genesis"; "no_repo" → a readable bucket.
    private static func projectName(fromWorkspace dir: String) -> String {
        if dir == "no_repo" { return "Windsurf · 游离文件" }
        if dir.count > 41 {
            let idx = dir.index(dir.endIndex, offsetBy: -41)
            let suffix = dir[idx...]
            if suffix.first == "_", suffix.dropFirst().count == 40,
               suffix.dropFirst().allSatisfy({ $0.isHexDigit }) {
                return String(dir[..<idx])
            }
        }
        return dir
    }

    /// Tracked copies are named "<32-hex content hash>_<original name>" — strip the prefix.
    private static func cleanFileName(_ n: String) -> String {
        guard n.count > 33 else { return n }
        let idx = n.index(n.startIndex, offsetBy: 32)
        if n[n.startIndex..<idx].allSatisfy({ $0.isHexDigit }), n[idx] == "_" {
            return String(n[n.index(after: idx)...])
        }
        return n
    }
}

/// Purely lexical path cleanup — deliberately does NOT touch the filesystem.
/// (NSString.standardizingPath resolves symlinks by stat-ing each component, which would
/// trip the macOS Documents/Desktop TCC prompt for every project cwd under ~/Documents.)
private func normalize(_ path: String) -> String {
    var p = path
    if p.hasPrefix("~") {
        p = NSHomeDirectory() + p.dropFirst()
    }
    // Collapse duplicate slashes and strip a trailing slash, lexically only.
    while p.contains("//") { p = p.replacingOccurrences(of: "//", with: "/") }
    while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
    return p
}

// MARK: - Scan engine with mtime cache

struct CacheEntry: Codable {
    var mtime: TimeInterval
    var size: Int
    var record: SessionRecord?   // nil = tombstone: file parsed, no usable session
}

enum ScanEngine {
    static var supportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vitrine")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var cacheURL: URL { supportDir.appendingPathComponent("scan-cache-v2.json") }

    static func loadCache() -> [String: CacheEntry] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [:] }
        return (try? JSONDecoder().decode([String: CacheEntry].self, from: data)) ?? [:]
    }

    static func saveCache(_ cache: [String: CacheEntry]) {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    static func fileStat(_ url: URL) -> (mtime: TimeInterval, size: Int)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let m = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let s = (attrs[.size] as? Int) ?? 0
        return (m, s)
    }

    struct Prepared {
        var cachedRecords: [SessionRecord]
        var pending: [(URL, AgentKind)]
        var cache: [String: CacheEntry]
    }

    /// Phase 1 (fast): discover files, split into cache hits vs. files needing a parse.
    static func prepare() -> Prepared {
        let cache = loadCache()
        var cached: [SessionRecord] = []
        var pending: [(URL, AgentKind)] = []
        let jobs: [(URL, AgentKind)] =
            ClaudeScanner.discover().map { ($0, .claude) } +
            CodexScanner.discover().map { ($0, .codex) }
        for (url, kind) in jobs {
            if let stat = fileStat(url), let entry = cache[url.path],
               entry.mtime == stat.mtime, entry.size == stat.size {
                if let r = entry.record { cached.append(r) }
            } else {
                pending.append((url, kind))
            }
        }
        return Prepared(cachedRecords: cached, pending: pending, cache: cache)
    }

    /// Phase 2 (slow): parse pending files in parallel. Streams batches of parsed records
    /// via `onBatch`, persists the cache incrementally, and returns the final cache.
    static func parse(
        _ pending: [(URL, AgentKind)],
        cache initialCache: [String: CacheEntry],
        progress: @escaping @Sendable (Double, String) -> Void,
        onBatch: @escaping @Sendable ([SessionRecord]) -> Void
    ) async {
        guard !pending.isEmpty else { return }
        var cache = initialCache
        let total = pending.count
        let done = ManagedAtomicCounter()

        var batch: [SessionRecord] = []
        var sinceSave = 0

        await withTaskGroup(of: (String, CacheEntry)?.self) { group in
            var iterator = pending.makeIterator()
            var inFlight = 0
            func addNext(_ g: inout TaskGroup<(String, CacheEntry)?>) {
                guard let (url, kind) = iterator.next() else { return }
                inFlight += 1
                g.addTask {
                    let rec: SessionRecord? = kind == .claude ? ClaudeScanner.scan(url) : CodexScanner.scan(url)
                    let n = done.increment()
                    progress(Double(n) / Double(total), "解析中 \(n)/\(total)…")
                    guard let stat = fileStat(url) else { return nil }
                    return (url.path, CacheEntry(mtime: stat.mtime, size: stat.size, record: rec))
                }
            }
            for _ in 0..<8 { addNext(&group) }
            while inFlight > 0 {
                guard let result = await group.next() else { break }
                inFlight -= 1
                addNext(&group)
                if let (path, entry) = result {
                    cache[path] = entry
                    if let r = entry.record { batch.append(r) }
                    sinceSave += 1
                    if batch.count >= 12 {
                        onBatch(batch)
                        batch.removeAll()
                    }
                    if sinceSave >= 60 {
                        saveCache(cache)
                        sinceSave = 0
                    }
                }
            }
        }
        if !batch.isEmpty { onBatch(batch) }
        saveCache(cache)
    }
}

final class ManagedAtomicCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
