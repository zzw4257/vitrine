import Foundation

// MARK: - Pin registry (shared with the installed CLI skills — see PinInstaller below)

/// A conversation the user explicitly "pinned" from inside a running CLI session, via the
/// installed vitrine-pin skill/command. The registry is a small JSON file both the CLI-side
/// script and Vitrine read/write: `~/Library/Application Support/Vitrine/pins.json`, keyed by the
/// transcript's file path (stable across Vitrine's own internal id scheme, and trivial for a
/// shell script to produce — it's exactly the file the script just found).
struct PinRecord: Codable, Hashable {
    var agent: String
    var label: String
    var pinnedAt: String   // ISO-8601, parsed with JSONL.date — matches the scanners' own convention
}

extension AppStore {
    private var pinsURL: URL { ScanEngine.supportDir.appendingPathComponent("pins.json") }

    func loadPins() {
        guard pins.isEmpty,
              let data = try? Data(contentsOf: pinsURL),
              let dict = try? JSONDecoder().decode([String: PinRecord].self, from: data) else { return }
        pins = dict
    }

    private func savePins() {
        if let data = try? JSONEncoder().encode(pins) {
            try? data.write(to: pinsURL, options: .atomic)
        }
    }

    func renamePin(_ filePath: String, label: String) {
        guard var p = pins[filePath] else { return }
        p.label = label
        pins[filePath] = p
        savePins()
    }

    func unpin(_ filePath: String) {
        pins.removeValue(forKey: filePath)
        savePins()
    }

    /// Every pin joined against the current scan, newest-pinned first. A pin whose transcript
    /// hasn't been scanned yet (or was moved/deleted) still shows, unresolved, rather than
    /// silently vanishing — the pin itself is the source of truth, the session match is a bonus.
    var pinnedEntries: [(filePath: String, pin: PinRecord, session: SessionRecord?)] {
        let byPath = Dictionary(allSessions.map { ($0.filePath, $0) }, uniquingKeysWith: { a, _ in a })
        return pins
            .map { (filePath: $0.key, pin: $0.value, session: byPath[$0.key]) }
            .sorted { (JSONL.date($0.pin.pinnedAt) ?? .distantPast) > (JSONL.date($1.pin.pinnedAt) ?? .distantPast) }
    }
}

// MARK: - Cross-CLI resume

/// Builds the exact resume invocation for each terminal-native agent, sourced from each CLI's
/// current official docs (Claude Code `sessions`/`cli-reference`, Codex `cli/reference`, gemini-cli
/// `cli/session-management`, opencode `cli/`). Cursor/Windsurf are IDEs without an equivalent
/// scriptable resume, so they're intentionally absent here.
enum PinResume {
    /// Extract the session id `--resume`/`--session` expects from a resolved session's transcript
    /// file path. Claude/opencode: the id IS the filename stem. Codex: the id is the UUID suffix
    /// of `rollout-<timestamp>-<uuid>.jsonl`. Gemini: the stem, minus a leading "session-".
    static func sessionId(agent: AgentKind, filePath: String) -> String? {
        let stem = (filePath as NSString).lastPathComponent.replacingOccurrences(of: ".jsonl", with: "")
            .replacingOccurrences(of: ".json", with: "")
        switch agent {
        case .claude, .opencode:
            return stem
        case .codex:
            guard let range = stem.range(
                of: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
                options: .regularExpression) else { return nil }
            return String(stem[range])
        case .gemini:
            return stem.hasPrefix("session-") ? String(stem.dropFirst("session-".count)) : stem
        default:
            return nil
        }
    }

    /// The full shell command to resume this exact session, run from the session's project dir.
    static func command(agent: AgentKind, sessionId: String) -> String? {
        switch agent {
        case .claude: return "claude --resume \(CLI.shellQuote(sessionId))"
        case .codex: return "codex resume \(CLI.shellQuote(sessionId))"
        case .gemini: return "gemini --resume \(CLI.shellQuote(sessionId))"
        case .opencode: return "opencode --session \(CLI.shellQuote(sessionId))"
        default: return nil
        }
    }
}

// MARK: - Installing the pin skill/command into each CLI

enum PinInstaller {
    enum Confidence { case verified, bestEffort }

    /// Which agents ship a pin integration, and how sure we are it's right. Claude Code and Codex
    /// are sourced from exact, current official docs (session-id substitution / rollout format).
    /// Gemini CLI and opencode use documented custom-command mechanisms but an unverified
    /// file-heuristic for "which session is this" — label them honestly rather than pretend parity.
    static let supported: [(agent: AgentKind, confidence: Confidence)] = [
        (.claude, .verified), (.codex, .verified), (.gemini, .bestEffort), (.opencode, .bestEffort),
    ]

    enum InstallError: LocalizedError {
        case unsupported
        var errorDescription: String? { "该 Agent 暂不支持一键安装 Pin 技能" }
    }

    /// Writes the skill/command bundle for one agent. Returns the primary file written (for the
    /// confirmation toast) — mirrors `Distiller.inject`'s backup-then-write convention.
    @discardableResult
    static func install(for agent: AgentKind) throws -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        func write(_ dir: URL, _ name: String, _ content: String, executable: Bool = false) throws {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(name)
            try Distiller.backupIfExists(file)
            try content.write(to: file, atomically: true, encoding: .utf8)
            if executable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            }
        }

        switch agent {
        case .claude:
            let dir = home.appendingPathComponent(".claude/skills/vitrine-pin")
            try write(dir, "SKILL.md", Self.claudeSkillMD)
            try write(dir.appendingPathComponent("scripts"), "pin.sh", Self.claudePinScript, executable: true)
            try write(pinAppenderDir(home), "pin-append.py", Self.pinAppenderPy, executable: true)
            return dir.appendingPathComponent("SKILL.md").path

        case .codex:
            let dir = home.appendingPathComponent(".agents/skills/vitrine-pin")
            try write(dir, "SKILL.md", Self.codexSkillMD)
            try write(dir.appendingPathComponent("scripts"), "pin.sh", Self.codexPinScript, executable: true)
            try write(pinAppenderDir(home), "pin-append.py", Self.pinAppenderPy, executable: true)
            return dir.appendingPathComponent("SKILL.md").path

        case .gemini:
            let helperDir = home.appendingPathComponent(".gemini/vitrine-pin")
            try write(helperDir, "pin.sh", Self.geminiPinScript, executable: true)
            try write(home.appendingPathComponent(".gemini/commands"), "vitrine-pin.toml", Self.geminiCommandTOML)
            try write(pinAppenderDir(home), "pin-append.py", Self.pinAppenderPy, executable: true)
            return home.appendingPathComponent(".gemini/commands/vitrine-pin.toml").path

        case .opencode:
            let helperDir = home.appendingPathComponent(".config/opencode/vitrine-pin")
            try write(helperDir, "pin.sh", Self.opencodePinScript, executable: true)
            try write(home.appendingPathComponent(".config/opencode/commands"), "vitrine-pin.md", Self.opencodeCommandMD)
            try write(pinAppenderDir(home), "pin-append.py", Self.pinAppenderPy, executable: true)
            return home.appendingPathComponent(".config/opencode/commands/vitrine-pin.md").path

        default:
            throw InstallError.unsupported
        }
    }

    private static func pinAppenderDir(_ home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Vitrine")
    }

    // MARK: Shared registry writer (one implementation, called by every agent's pin.sh)

    static let pinAppenderPy = """
    #!/usr/bin/env python3
    # Shared by every Vitrine pin integration (Claude/Codex/Gemini/opencode) — appends one entry
    # to the pins registry that Vitrine.app itself reads. Safe to run standalone for testing:
    #   python3 pin-append.py claude /path/to/transcript.jsonl "my label"
    import json, os, sys, datetime

    REGISTRY = os.path.expanduser("~/Library/Application Support/Vitrine/pins.json")

    def main():
        if len(sys.argv) < 3:
            print("usage: pin-append.py <agent> <file-path> [label]", file=sys.stderr)
            sys.exit(1)
        agent, file_path = sys.argv[1], sys.argv[2]
        label = sys.argv[3].strip() if len(sys.argv) > 3 and sys.argv[3].strip() else os.path.basename(file_path)

        os.makedirs(os.path.dirname(REGISTRY), exist_ok=True)
        try:
            with open(REGISTRY) as f:
                pins = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            pins = {}

        pins[file_path] = {
            "agent": agent,
            "label": label,
            "pinnedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }

        tmp = REGISTRY + ".tmp"
        with open(tmp, "w") as f:
            json.dump(pins, f, ensure_ascii=False, indent=2)
        os.replace(tmp, REGISTRY)
        print(f'Pinned in Vitrine as "{label}".')

    if __name__ == "__main__":
        main()
    """

    // MARK: Claude Code — exact session id via the documented ${CLAUDE_SESSION_ID} substitution

    static let claudeSkillMD = """
    ---
    name: vitrine-pin
    description: Pin the current conversation so it shows up in Vitrine's Pinned view with a custom label, ready to resume with one click. Use when the user asks to "pin this", "star this conversation", "置顶这个对话", or similar.
    disable-model-invocation: false
    ---

    When the user asks to pin this conversation, run exactly (substituting a short label you infer
    from the conversation, or one the user gave verbatim):

    ```
    bash "${CLAUDE_SKILL_DIR}/scripts/pin.sh" "${CLAUDE_SESSION_ID}" <label>
    ```

    Report back whatever the script printed. If it failed (session not flushed to disk yet), tell
    the user to try again in a few seconds.
    """

    static let claudePinScript = """
    #!/bin/bash
    # Installed by Vitrine (vitrine-pin skill). Locates this session's own transcript by its id —
    # Claude Code substitutes ${CLAUDE_SESSION_ID} into SKILL.md before the model ever sees it, and
    # that id IS the transcript's filename stem (code.claude.com/docs/en/sessions), so no cwd/mtime
    # guessing is needed here, unlike the other agents' pin scripts.
    set -euo pipefail
    SESSION_ID="${1:?session id required}"; shift || true
    LABEL="${*:-}"

    FILE_PATH=$(find "$HOME/.claude/projects" -maxdepth 2 -name "${SESSION_ID}.jsonl" -print -quit 2>/dev/null || true)
    if [ -z "$FILE_PATH" ]; then
        echo "Could not find transcript for session $SESSION_ID yet — try again shortly." >&2
        exit 1
    fi
    python3 "$HOME/Library/Application Support/Vitrine/pin-append.py" claude "$FILE_PATH" "$LABEL"
    """

    // MARK: Codex — Skills-recommended layout; session id resolved by matching cwd in rollout files
    // (Codex has no session-id substitution for skills as of this writing — openai/codex
    // Discussion #3827 confirms there's no supported way for a running session to learn its own id).

    static let codexSkillMD = """
    ---
    name: vitrine-pin
    description: Pin the current conversation so it shows up in Vitrine's Pinned view with a custom label, ready to resume with one click. Use when the user asks to pin, star, or bookmark this conversation.
    ---

    When the user asks to pin this conversation, run exactly (substituting a short label you infer
    from the conversation, or one the user gave verbatim):

    ```
    bash "$HOME/.agents/skills/vitrine-pin/scripts/pin.sh" <label>
    ```

    This looks up the newest Codex session rooted at the current working directory — it is a
    best-effort match, not an exact id (Codex CLI doesn't expose a session's own id to itself).
    Report back whatever the script printed.
    """

    static let codexPinScript = """
    #!/bin/bash
    # Installed by Vitrine (vitrine-pin skill). Codex has no documented way for a running session
    # to learn its own id, so this finds the most-recently-modified rollout file whose recorded
    # cwd matches $PWD (each rollout's first line is a session_meta record with a "cwd" field —
    # developers.openai.com/codex + deepwiki.com/openai/codex/3.5.2-rollout-persistence-and-replay).
    # Best-effort: two Codex sessions open in the exact same directory at once would race here.
    set -euo pipefail
    LABEL="${*:-}"
    CWD="$(pwd)"
    FILE_PATH=""
    BEST_MTIME=0

    while IFS= read -r -d '' f; do
        META_CWD=$(head -n1 "$f" 2>/dev/null | python3 -c '
    import json, sys
    try:
        d = json.loads(sys.stdin.read())
        print(d.get("payload", {}).get("cwd", ""))
    except Exception:
        print("")
    ' 2>/dev/null || true)
        if [ "$META_CWD" = "$CWD" ]; then
            MTIME=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
            if [ "$MTIME" -gt "$BEST_MTIME" ]; then BEST_MTIME=$MTIME; FILE_PATH="$f"; fi
        fi
    done < <(find "$HOME/.codex/sessions" -name "rollout-*.jsonl" -print0 2>/dev/null)

    if [ -z "$FILE_PATH" ]; then
        echo "Could not find a Codex session rooted at $CWD." >&2
        exit 1
    fi
    python3 "$HOME/Library/Application Support/Vitrine/pin-append.py" codex "$FILE_PATH" "$LABEL"
    """

    // MARK: Gemini CLI — custom TOML command with `!{...}` shell injection

    static let geminiCommandTOML = """
    description = "Pin this conversation in Vitrine with a custom label"
    prompt = \"\"\"
    !{bash "$HOME/.gemini/vitrine-pin/pin.sh" "{{args}}"}
    Relay the line above to the user as the result of pinning this conversation.
    \"\"\"
    """

    static let geminiPinScript = """
    #!/bin/bash
    # Installed by Vitrine (/vitrine-pin custom command). Gemini CLI session/chat files live at
    # ~/.gemini/tmp/<sha256(cwd)>/chats/session-*.json (github.com/google-gemini/gemini-cli docs/
    # cli/session-management.md) — best-effort: picks the newest chat file for this directory's hash.
    set -euo pipefail
    LABEL="${*:-}"
    CWD="$(pwd)"
    HASH=$(printf '%s' "$CWD" | shasum -a 256 | cut -d' ' -f1)
    DIR="$HOME/.gemini/tmp/$HASH/chats"
    FILE_PATH=$(ls -t "$DIR"/session-*.json 2>/dev/null | head -n1 || true)

    if [ -z "$FILE_PATH" ]; then
        echo "Could not find a Gemini CLI chat file for $CWD." >&2
        exit 1
    fi
    python3 "$HOME/Library/Application Support/Vitrine/pin-append.py" gemini "$FILE_PATH" "$LABEL"
    """

    // MARK: opencode — markdown custom command with `` !`cmd` `` shell injection

    static let opencodeCommandMD = """
    ---
    description: Pin this conversation in Vitrine with a custom label
    ---
    !`bash "$HOME/.config/opencode/vitrine-pin/pin.sh" "$ARGUMENTS"`
    """

    static let opencodePinScript = """
    #!/bin/bash
    # Installed by Vitrine (/vitrine-pin custom command). opencode stores sessions at
    # ~/.local/share/opencode/storage/session/<projectID>/<sessionID>.json (opencode.ai/docs/ +
    # source at packages/opencode/src/storage/storage.ts) — best-effort: picks the single
    # most-recently-modified session file across ALL projects, since the projectID isn't otherwise
    # derivable from the shell. Fine for one active opencode session; imprecise with several at once.
    set -euo pipefail
    LABEL="${*:-}"
    FILE_PATH=$(find "$HOME/.local/share/opencode/storage/session" -name "*.json" -print0 2>/dev/null \\
        | xargs -0 ls -t 2>/dev/null | head -n1 || true)

    if [ -z "$FILE_PATH" ]; then
        echo "Could not find an opencode session file." >&2
        exit 1
    fi
    python3 "$HOME/Library/Application Support/Vitrine/pin-append.py" opencode "$FILE_PATH" "$LABEL"
    """
}
