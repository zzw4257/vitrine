import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Full-text index over session titles + user prompts, FTS5 trigram (CJK-friendly),
/// with LIKE fallback for queries shorter than 3 characters.
final class SearchIndex: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()

    init?(path: String) {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            return nil
        }
        exec("PRAGMA journal_mode=WAL")
        exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS docs USING fts5(
                session_id UNINDEXED, agent UNINDEXED, project UNINDEXED,
                title, content, tokenize='trigram')
            """)
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    func rebuild(_ records: [SessionRecord]) {
        lock.lock(); defer { lock.unlock() }
        exec("BEGIN")
        exec("DELETE FROM docs")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "INSERT INTO docs(session_id, agent, project, title, content) VALUES(?,?,?,?,?)",
            -1, &stmt, nil) == SQLITE_OK else { exec("ROLLBACK"); return }
        defer { sqlite3_finalize(stmt) }
        for r in records {
            // Include the footprint (files + commands) so summary-only / transcript-less agents
            // (Cursor, Windsurf) are still findable by what they touched.
            let content = ([r.userPrompts.joined(separator: "\n"), r.summary ?? "",
                            r.filesTouched.joined(separator: " "),
                            r.bashCommands.joined(separator: "\n")]
                .filter { !$0.isEmpty }.joined(separator: "\n"))
            sqlite3_bind_text(stmt, 1, r.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, r.agent.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, r.projectPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, r.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, String(content.prefix(20_000)), -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
        exec("COMMIT")
    }

    struct Filter {
        var agent: AgentKind? = nil
        var project: String? = nil
    }

    func search(_ query: String, filter: Filter = Filter(), limit: Int = 80) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        lock.lock(); defer { lock.unlock() }
        return q.count >= 3 ? ftsSearch(q, filter: filter, limit: limit)
                            : likeSearch(q, filter: filter, limit: limit)
    }

    private func ftsSearch(_ q: String, filter: Filter, limit: Int) -> [SearchHit] {
        var sql = """
            SELECT session_id, snippet(docs, 4, '⟦', '⟧', ' … ', 14), bm25(docs)
            FROM docs WHERE docs MATCH ?
            """
        if filter.agent != nil { sql += " AND agent = ?" }
        if filter.project != nil { sql += " AND project = ?" }
        sql += " ORDER BY bm25(docs) LIMIT \(limit)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let phrase = "\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        var idx: Int32 = 1
        sqlite3_bind_text(stmt, idx, phrase, -1, SQLITE_TRANSIENT); idx += 1
        if let a = filter.agent { sqlite3_bind_text(stmt, idx, a.rawValue, -1, SQLITE_TRANSIENT); idx += 1 }
        if let p = filter.project { sqlite3_bind_text(stmt, idx, p, -1, SQLITE_TRANSIENT); idx += 1 }

        var out: [SearchHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let sid = sqlite3_column_text(stmt, 0) else { continue }
            let snip = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let rank = sqlite3_column_double(stmt, 2)
            out.append(SearchHit(sessionId: String(cString: sid), snippet: snip, rank: -rank))
        }
        return out
    }

    private func likeSearch(_ q: String, filter: Filter, limit: Int) -> [SearchHit] {
        var sql = "SELECT session_id, title, content FROM docs WHERE (title LIKE ? OR content LIKE ?)"
        if filter.agent != nil { sql += " AND agent = ?" }
        if filter.project != nil { sql += " AND project = ?" }
        sql += " LIMIT \(limit)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let escaped = q
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"
        var idx: Int32 = 1
        sqlite3_bind_text(stmt, idx, pattern, -1, SQLITE_TRANSIENT); idx += 1
        sqlite3_bind_text(stmt, idx, pattern, -1, SQLITE_TRANSIENT); idx += 1
        if let a = filter.agent { sqlite3_bind_text(stmt, idx, a.rawValue, -1, SQLITE_TRANSIENT); idx += 1 }
        if let p = filter.project { sqlite3_bind_text(stmt, idx, p, -1, SQLITE_TRANSIENT); idx += 1 }

        var out: [SearchHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let sid = sqlite3_column_text(stmt, 0) else { continue }
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let content = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let snippet = Self.manualSnippet(q, in: content) ?? title
            out.append(SearchHit(sessionId: String(cString: sid), snippet: snippet, rank: 0))
        }
        return out
    }

    private static func manualSnippet(_ q: String, in text: String) -> String? {
        guard let range = text.range(of: q, options: .caseInsensitive) else { return nil }
        let lo = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let hi = text.index(range.upperBound, offsetBy: 50, limitedBy: text.endIndex) ?? text.endIndex
        return "…" + text[lo..<hi].replacingOccurrences(of: "\n", with: " ") + "…"
    }
}
