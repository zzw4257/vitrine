import SwiftUI

// MARK: - LaTeX → styled Text (dependency-free)

/// Renders inline LaTeX math into a SwiftUI `Text` using Unicode symbol substitution plus
/// real super/subscripts (baseline offset + smaller size). Covers the math that actually shows
/// up in research chat — Greek, operators, sub/superscripts, \frac, \sqrt, \mathbb/\mathbf,
/// accents — without a web view or external engine. Not a full TeX typesetter; a faithful reader.
enum Math {
    /// Multi-char LaTeX commands → Unicode. Longest keys matched first.
    static let symbols: [String: String] = [
        // greek lower
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ", "\\epsilon": "ε",
        "\\varepsilon": "ε", "\\zeta": "ζ", "\\eta": "η", "\\theta": "θ", "\\vartheta": "ϑ",
        "\\iota": "ι", "\\kappa": "κ", "\\lambda": "λ", "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ",
        "\\pi": "π", "\\rho": "ρ", "\\sigma": "σ", "\\tau": "τ", "\\upsilon": "υ", "\\phi": "φ",
        "\\varphi": "φ", "\\chi": "χ", "\\psi": "ψ", "\\omega": "ω",
        // greek upper
        "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ", "\\Xi": "Ξ",
        "\\Pi": "Π", "\\Sigma": "Σ", "\\Phi": "Φ", "\\Psi": "Ψ", "\\Omega": "Ω",
        // operators / relations
        "\\times": "×", "\\cdot": "·", "\\div": "÷", "\\pm": "±", "\\mp": "∓",
        "\\leq": "≤", "\\le": "≤", "\\geq": "≥", "\\ge": "≥", "\\neq": "≠", "\\ne": "≠",
        "\\approx": "≈", "\\equiv": "≡", "\\sim": "∼", "\\propto": "∝", "\\ll": "≪", "\\gg": "≫",
        "\\rightarrow": "→", "\\to": "→", "\\leftarrow": "←", "\\Rightarrow": "⇒",
        "\\Leftarrow": "⇐", "\\leftrightarrow": "↔", "\\mapsto": "↦", "\\implies": "⇒",
        "\\infty": "∞", "\\partial": "∂", "\\nabla": "∇", "\\forall": "∀", "\\exists": "∃",
        "\\in": "∈", "\\notin": "∉", "\\subset": "⊂", "\\subseteq": "⊆", "\\supset": "⊃",
        "\\cup": "∪", "\\cap": "∩", "\\emptyset": "∅", "\\varnothing": "∅",
        "\\sum": "∑", "\\prod": "∏", "\\int": "∫", "\\oint": "∮", "\\iint": "∬",
        "\\sqrt": "√", "\\angle": "∠", "\\perp": "⊥", "\\parallel": "∥",
        "\\land": "∧", "\\lor": "∨", "\\lnot": "¬", "\\oplus": "⊕", "\\otimes": "⊗",
        "\\star": "⋆", "\\ast": "∗", "\\circ": "∘", "\\bullet": "•", "\\dots": "…",
        "\\ldots": "…", "\\cdots": "⋯", "\\prime": "′", "\\deg": "°", "\\hbar": "ℏ",
        "\\ell": "ℓ", "\\Re": "ℜ", "\\Im": "ℑ", "\\aleph": "ℵ", "\\nabla": "∇",
        "\\leftrightarrow": "↔", "\\Leftrightarrow": "⇔", "\\langle": "⟨", "\\rangle": "⟩",
        // blackboard bold (common sets)
        "\\mathbb{R}": "ℝ", "\\mathbb{N}": "ℕ", "\\mathbb{Z}": "ℤ", "\\mathbb{Q}": "ℚ",
        "\\mathbb{C}": "ℂ", "\\mathbb{E}": "𝔼", "\\mathbb{P}": "ℙ", "\\mathbb{R}^n": "ℝⁿ",
        // spacing / misc that should vanish
        "\\,": " ", "\\;": " ", "\\:": " ", "\\!": "", "\\quad": "  ", "\\qquad": "    ",
        "\\left": "", "\\right": "", "\\displaystyle": "", "\\text": "", "\\mathrm": "",
    ]

    private static let superMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷",
        "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ",
    ]
    private static let subMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇",
        "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
    ]

    /// Expand \frac and \sqrt (which take braced args) before symbol substitution.
    private static func expandCommands(_ s: String) -> String {
        var out = s
        // \frac{A}{B} -> A⁄B  (fraction slash); repeat for nesting
        while let r = out.range(of: "\\frac") {
            guard let (a, after1) = braced(out, from: r.upperBound),
                  let (b, after2) = braced(out, from: after1) else { break }
            let numer = a.count > 1 ? "(\(a))" : a
            let denom = b.count > 1 ? "(\(b))" : b
            out.replaceSubrange(r.lowerBound..<after2, with: "\(numer)⁄\(denom)")
        }
        while let r = out.range(of: "\\sqrt") {
            guard let (a, after) = braced(out, from: r.upperBound) else { break }
            out.replaceSubrange(r.lowerBound..<after, with: "√(\(a))")
        }
        return out
    }

    /// If `idx` sits at `{`, return the (contents, indexAfterClosingBrace).
    private static func braced(_ s: String, from idx: String.Index) -> (String, String.Index)? {
        guard idx < s.endIndex, s[idx] == "{" else { return nil }
        var depth = 0, i = idx
        var content = ""
        while i < s.endIndex {
            let c = s[i]
            if c == "{" { depth += 1; if depth > 1 { content.append(c) } }
            else if c == "}" { depth -= 1; if depth == 0 { return (content, s.index(after: i)) }; content.append(c) }
            else { content.append(c) }
            i = s.index(after: i)
        }
        return nil
    }

    private static func substituteSymbols(_ s: String) -> String {
        var out = s
        for key in symbols.keys.sorted(by: { $0.count > $1.count }) {
            out = out.replacingOccurrences(of: key, with: symbols[key]!)
        }
        // strip stray braces and any leftover backslash-commands (keep the name)
        out = out.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        out = out.replacingOccurrences(of: "\\", with: "")
        return out
    }

    /// Build a SwiftUI Text for an inline math string.
    static func text(_ latex: String, size: CGFloat, color: Color) -> Text {
        let normalized = substituteSymbols(expandCommands(latex))
        var result = Text("")
        let chars = Array(normalized)
        var i = 0
        let base = Font.system(size: size, design: .serif).italic()
        let small = Font.system(size: size * 0.72, design: .serif)

        func groupAfter(_ start: Int) -> (String, Int) {
            // Returns the scripted content and index past it. Handles single char (already de-braced).
            guard start < chars.count else { return ("", start) }
            return (String(chars[start]), start + 1)
        }

        while i < chars.count {
            let c = chars[i]
            if c == "^" || c == "_" {
                let (grp, next) = groupAfter(i + 1)
                let mapped = grp.map { (c == "^" ? superMap[$0] : subMap[$0]) ?? $0 }
                if String(mapped) == grp {
                    // No Unicode script glyph — fall back to baseline offset styling.
                    result = result + Text(grp).font(small).baselineOffset(c == "^" ? size * 0.34 : -size * 0.16)
                } else {
                    result = result + Text(String(mapped)).font(base)
                }
                i = next
            } else {
                result = result + Text(String(c)).font(base)
                i += 1
            }
        }
        return result.foregroundColor(color)
    }
}

// MARK: - Syntax highlighting for code / shell

enum Syntax {
    // Fixed mid-saturation hues that read on both light and dark canvases.
    static let cmd = Color(red: 0.30, green: 0.78, blue: 0.70)     // command head — teal
    static let flag = Color(red: 0.98, green: 0.68, blue: 0.30)    // -flags — amber
    static let str = Color(red: 0.45, green: 0.78, blue: 0.45)     // "strings" — green
    static let path = Color(red: 0.40, green: 0.62, blue: 0.98)    // paths — blue
    static let num = Color(red: 0.72, green: 0.55, blue: 1.0)      // numbers — violet
    static let comment = Color.secondary
    static let op = Color.secondary                                // | & > < ;

    /// Colorize one line of shell/code into a monospaced Text.
    static func line(_ s: String, size: CGFloat) -> Text {
        let font = Font.system(size: size, design: .monospaced)
        // Whole-line comment
        if s.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            return Text(s).font(font).foregroundColor(comment)
        }
        var result = Text("")
        var isFirstToken = true
        for (tok, sep) in tokens(s) {
            result = result + colored(tok, font: font, first: isFirstToken)
            if !tok.isEmpty { isFirstToken = false }
            // reset "first token" after a pipe/;/&& so the next command head colors too
            if ["|", ";", "&&", "||"].contains(tok) { isFirstToken = true }
            if !sep.isEmpty { result = result + Text(sep).font(font) }
        }
        return result
    }

    private static func colored(_ t: String, font: Font, first: Bool) -> Text {
        guard !t.isEmpty else { return Text("") }
        if t.hasPrefix("\"") || t.hasPrefix("'") { return Text(t).font(font).foregroundColor(str) }
        if t.hasPrefix("-") { return Text(t).font(font).foregroundColor(flag) }
        if ["|", "&&", "||", ";", ">", ">>", "<", "&"].contains(t) { return Text(t).font(font).foregroundColor(op) }
        if t.allSatisfy({ $0.isNumber || $0 == "." }) { return Text(t).font(font).foregroundColor(num) }
        if first { return Text(t).font(font.weight(.semibold)).foregroundColor(cmd) }
        if t.contains("/") { return Text(t).font(font).foregroundColor(path) }
        return Text(t).font(font).foregroundColor(.primary.opacity(0.85))
    }

    /// Split into (token, trailingWhitespace), keeping quoted spans intact.
    private static func tokens(_ s: String) -> [(String, String)] {
        var out: [(String, String)] = []
        let chars = Array(s); var i = 0
        while i < chars.count {
            if chars[i] == " " || chars[i] == "\t" {
                var ws = ""; while i < chars.count, chars[i] == " " || chars[i] == "\t" { ws.append(chars[i]); i += 1 }
                if out.isEmpty { out.append(("", ws)) } else { out[out.count - 1].1 += ws }
                continue
            }
            var tok = ""
            if chars[i] == "\"" || chars[i] == "'" {
                let q = chars[i]; tok.append(q); i += 1
                while i < chars.count { tok.append(chars[i]); if chars[i] == q { i += 1; break }; i += 1 }
            } else {
                while i < chars.count, chars[i] != " ", chars[i] != "\t" { tok.append(chars[i]); i += 1 }
            }
            out.append((tok, ""))
        }
        return out
    }
}

/// A recessed, syntax-highlighted code card with an optional language tag.
struct CodeBlock: View {
    @Environment(ThemeManager.self) private var theme
    var code: String
    var language: String? = nil
    var size: CGFloat = 11.5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language {
                HStack {
                    Text(language.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.textFaint).tracking(0.5)
                    Spacer()
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 8)).foregroundStyle(theme.textFaint)
                }
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(theme.hairline)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(code.components(separatedBy: "\n").enumerated()), id: \.offset) { _, ln in
                    Syntax.line(ln, size: size)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
        }
        .background(theme.well, in: .rect(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.hairline, lineWidth: 0.5))
    }
}

// MARK: - Rich text (markdown + LaTeX) block renderer

/// Renders a markdown string that may contain LaTeX. Headings, bullets, inline `code`, **bold**,
/// *italic*, fenced code, and `$…$` / `$$…$$` / `\(…\)` / `\[…\]` math all render.
struct RichText: View {
    var text: String
    var size: CGFloat = 12.5
    var textColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                block(b)
            }
        }
    }

    private enum Block: Equatable {
        case heading(Int, String)
        case bullet(String)
        case code(String)
        case display(String)   // $$ … $$ display math
        case para(String)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var paraBuf: [String] = []
        func flushPara() {
            if !paraBuf.isEmpty { out.append(.para(paraBuf.joined(separator: " "))); paraBuf = [] }
        }
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                flushPara(); i += 1
                var code: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                out.append(.code(code.joined(separator: "\n"))); i += 1; continue
            }
            if t.hasPrefix("$$"), t.hasSuffix("$$"), t.count > 4 {
                flushPara()
                out.append(.display(String(t.dropFirst(2).dropLast(2)))); i += 1; continue
            }
            if let h = heading(t) { flushPara(); out.append(.heading(h.0, h.1)); i += 1; continue }
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ") {
                flushPara(); out.append(.bullet(String(t.dropFirst(2)))); i += 1; continue
            }
            if t.isEmpty { flushPara() } else { paraBuf.append(t) }
            i += 1
        }
        flushPara()
        return out
    }

    private func heading(_ t: String) -> (Int, String)? {
        var n = 0, s = Substring(t)
        while s.first == "#" { n += 1; s = s.dropFirst() }
        guard n > 0, s.first == " " else { return nil }
        return (min(n, 3), String(s.dropFirst()))
    }

    @ViewBuilder
    private func block(_ b: Block) -> some View {
        switch b {
        case .heading(let lvl, let s):
            inline(s).font(.system(size: size + CGFloat(4 - lvl) * 2, weight: .bold))
                .foregroundStyle(textColor)
        case .bullet(let s):
            HStack(alignment: .top, spacing: 7) {
                Circle().fill(textColor.opacity(0.5)).frame(width: 4, height: 4).padding(.top, size * 0.5)
                inline(s).foregroundStyle(textColor.opacity(0.92))
            }
        case .code(let s):
            CodeBlock(code: s, size: size - 0.5)
        case .display(let m):
            HStack {
                Spacer()
                Math.text(m, size: size + 4, color: textColor)
                Spacer()
            }
            .padding(.vertical, 3)
        case .para(let s):
            inline(s).foregroundStyle(textColor.opacity(0.92))
        }
    }

    /// Render a line of text: split on math delimiters, concat markdown runs + math runs into one Text.
    private func inline(_ s: String) -> Text {
        var result = Text("")
        for seg in segments(s) {
            switch seg {
            case .text(let t):
                if let attr = try? AttributedString(markdown: t,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    result = result + Text(attr)
                } else {
                    result = result + Text(t)
                }
            case .math(let m):
                result = result + Math.text(m, size: size, color: textColor)
            }
        }
        return result.font(.system(size: size))
    }

    private enum Seg { case text(String); case math(String) }

    /// Split a string into text and math segments by $…$ and \(…\) delimiters.
    private func segments(_ s: String) -> [Seg] {
        var out: [Seg] = []
        var buf = ""
        let chars = Array(s)
        var i = 0
        func flush() { if !buf.isEmpty { out.append(.text(buf)); buf = "" } }
        while i < chars.count {
            // \( … \)
            if i + 1 < chars.count, chars[i] == "\\", chars[i + 1] == "(" {
                if let end = findClose(chars, from: i + 2, close: ["\\", ")"]) {
                    flush(); out.append(.math(String(chars[(i + 2)..<end]))); i = end + 2; continue
                }
            }
            if i + 1 < chars.count, chars[i] == "\\", chars[i + 1] == "[" {
                if let end = findClose(chars, from: i + 2, close: ["\\", "]"]) {
                    flush(); out.append(.math(String(chars[(i + 2)..<end]))); i = end + 2; continue
                }
            }
            // $ … $ (single, not $$)
            if chars[i] == "$", !(i + 1 < chars.count && chars[i + 1] == "$") {
                if let end = firstIndex(chars, of: "$", from: i + 1) {
                    flush(); out.append(.math(String(chars[(i + 1)..<end]))); i = end + 1; continue
                }
            }
            buf.append(chars[i]); i += 1
        }
        flush()
        return out
    }

    private func firstIndex(_ chars: [Character], of ch: Character, from: Int) -> Int? {
        var i = from
        while i < chars.count { if chars[i] == ch { return i }; i += 1 }
        return nil
    }
    private func findClose(_ chars: [Character], from: Int, close: [Character]) -> Int? {
        var i = from
        while i + 1 < chars.count {
            if chars[i] == close[0], chars[i + 1] == close[1] { return i }
            i += 1
        }
        return nil
    }
}
