import Foundation

/// Only transforms we can prove are safe — never LLM guesses.
/// Applied in-process (no Node subprocess) so Auto-correct can't hang the UI.
enum VerifiedFixer {
    case removeExport
    case deleteDead
    case addEnvExample

    struct Result {
        let ok: Bool
        let file: String
        let message: String
    }

    static func fixer(for finding: Finding) -> VerifiedFixer? {
        guard finding.line != nil else { return nil }
        switch finding.fixHint {
        case .removeExport: return .removeExport
        case .deleteDead: return .deleteDead
        case .addEnvExample: return .addEnvExample
        default:
            // Fallback when an older cached report omitted fixHint.
            if finding.check == "dead-exports" {
                if finding.message.contains("only used within this file") {
                    return .removeExport
                }
                return .deleteDead
            }
            if finding.check == "env-drift" { return .addEnvExample }
            return nil
        }
    }

    var label: String {
        switch self {
        case .removeExport: return "Verified · strip export"
        case .deleteDead: return "Verified · delete dead code"
        case .addEnvExample: return "Verified · document env var"
        }
    }

    var detail: String {
        switch self {
        case .removeExport:
            return "Deterministic rewrite: removes the export keyword only."
        case .deleteDead:
            return "Deterministic rewrite: deletes the unused declaration block (brace-matched)."
        case .addEnvExample:
            return "Deterministic rewrite: adds the var name to .env.example (empty — no secrets)."
        }
    }

    var cliKind: String {
        switch self {
        case .removeExport: return "remove-export"
        case .deleteDead: return "delete-dead"
        case .addEnvExample: return "add-env-example"
        }
    }

    /// Apply against the folder the user opened (resolves companion paths).
    static func apply(repoPath: String, file: String, line: Int, kind: VerifiedFixer) -> Result {
        guard let resolved = Engine.resolveSource(repoPath: repoPath, file: file) else {
            return Result(ok: false, file: file, message: "Couldn't find \(file) on disk.")
        }
        switch kind {
        case .removeExport:
            return removeExport(abs: resolved.abs, rel: file, line: line)
        case .deleteDead:
            return deleteDead(abs: resolved.abs, rel: file, line: line)
        case .addEnvExample:
            return addEnvExample(root: resolved.root, abs: resolved.abs, rel: file, line: line)
        }
    }

    // MARK: - remove-export

    private static func removeExport(abs: String, rel: String, line: Int) -> Result {
        guard let text = try? String(contentsOfFile: abs, encoding: .utf8) else {
            return Result(ok: false, file: rel, message: "Could not read \(rel)")
        }
        // Preserve trailing newline presence
        let hadTrailing = text.hasSuffix("\n")
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if hadTrailing && lines.last == "" { lines.removeLast() }

        let idx = line - 1
        guard idx >= 0, idx < lines.count else {
            return Result(ok: false, file: rel, message: "Line \(line) out of range")
        }

        let original = lines[idx]
        if let next = stripExportKeyword(original), next != original {
            lines[idx] = next
            writeLines(lines, to: abs, trailingNewline: hadTrailing)
            return Result(ok: true, file: rel, message: "Removed export keyword at line \(line)")
        }

        // export { … } — comment out (safe, reversible)
        if let commented = commentExportList(original), commented != original {
            lines[idx] = commented
            writeLines(lines, to: abs, trailingNewline: hadTrailing)
            return Result(ok: true, file: rel, message: "Commented export list at line \(line)")
        }

        // Stale finding: export already stripped on a prior pass.
        if original.range(
            of: #"^\s*(async\s+)?function\b|^\s*(const|let|class|type|interface)\b"#,
            options: .regularExpression
        ) != nil {
            return Result(ok: true, file: rel, message: "Already fixed — no export on line \(line)")
        }

        return Result(ok: false, file: rel, message: "No removable export on line \(line)")
    }

    private static func stripExportKeyword(_ line: String) -> String? {
        // ^(\s*)export\s+(?=async function|function|const|let|class|type|interface)
        guard let regex = try? NSRegularExpression(
            pattern: #"^(\s*)export\s+(?=async\s+function|function|const|let|class|type|interface)"#
        ) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let next = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "$1")
        return next
    }

    private static func commentExportList(_ line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)export\s+\{"#) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let next = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "$1// was: export {")
        return next == line ? nil : next
    }

    // MARK: - delete-dead

    private static func deleteDead(abs: String, rel: String, line: Int) -> Result {
        guard let text = try? String(contentsOfFile: abs, encoding: .utf8) else {
            return Result(ok: false, file: rel, message: "Could not read \(rel)")
        }
        let hadTrailing = text.hasSuffix("\n")
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if hadTrailing && lines.last == "" { lines.removeLast() }

        let idx = line - 1
        guard idx >= 0, idx < lines.count else {
            return Result(ok: false, file: rel, message: "Line \(line) out of range")
        }

        let startLine = lines[idx]
        let isDecl =
            startLine.range(of: #"^\s*(export\s+)?(async\s+)?function\b"#, options: .regularExpression) != nil
            || startLine.range(of: #"^\s*(export\s+)?(const|let|class|type|interface)\b"#, options: .regularExpression) != nil
        guard isDecl else {
            return Result(
                ok: false,
                file: rel,
                message: "Line \(line) isn’t a deletable declaration (function/const/class/type)"
            )
        }

        let slice = lines[idx...].joined(separator: "\n")
        var endIdx = idx
        var brace = 0, paren = 0, bracket = 0
        var started = false
        var inStr: Character?
        var i = slice.startIndex

        while i < slice.endIndex {
            let ch = slice[i]
            let prev: Character? = i > slice.startIndex ? slice[slice.index(before: i)] : nil

            if let s = inStr {
                if ch == s && prev != "\\" { inStr = nil }
                i = slice.index(after: i)
                continue
            }
            if ch == "\"" || ch == "'" || ch == "`" {
                inStr = ch
                i = slice.index(after: i)
                continue
            }

            switch ch {
            case "{": brace += 1; started = true
            case "}": brace -= 1
            case "(": paren += 1; started = true
            case ")": paren -= 1
            case "[": bracket += 1; started = true
            case "]": bracket -= 1
            default: break
            }

            // const x = 1; (no brackets) — end at semicolon once past =
            let simpleAssign = startLine.range(of: #"=\s*[^({\[]"#, options: .regularExpression) != nil
            if !started && simpleAssign && (ch == ";" || ch == "\n") {
                let consumed = String(slice[slice.startIndex...i])
                endIdx = idx + consumed.split(separator: "\n", omittingEmptySubsequences: false).count - 1
                break
            }

            // Array/object/function body fully closed
            if started && brace <= 0 && paren <= 0 && bracket <= 0 {
                let consumed = String(slice[slice.startIndex...i])
                endIdx = idx + consumed.split(separator: "\n", omittingEmptySubsequences: false).count - 1
                if endIdx + 1 < lines.count && lines[endIdx + 1].range(of: #"^\s*;\s*$"#, options: .regularExpression) != nil {
                    endIdx += 1
                }
                break
            }

            i = slice.index(after: i)
        }

        guard endIdx >= idx else {
            return Result(ok: false, file: rel, message: "Could not find end of declaration at \(line)")
        }

        var from = idx
        var to = endIdx
        if from > 0 && lines[from - 1].trimmingCharacters(in: .whitespaces).isEmpty { from -= 1 }
        else if to + 1 < lines.count && lines[to + 1].trimmingCharacters(in: .whitespaces).isEmpty { to += 1 }

        lines.removeSubrange(from...to)
        writeLines(lines, to: abs, trailingNewline: hadTrailing)
        return Result(
            ok: true,
            file: rel,
            message: "Deleted dead declaration at lines \(from + 1)–\(to + 1)"
        )
    }

    // MARK: - add-env-example

    private static func addEnvExample(root: String, abs: String, rel: String, line: Int) -> Result {
        guard let text = try? String(contentsOfFile: abs, encoding: .utf8) else {
            return Result(ok: false, file: rel, message: "Could not read \(rel)")
        }
        let srcLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let idx = line - 1
        guard idx >= 0, idx < srcLines.count else {
            return Result(ok: false, file: rel, message: "Line \(line) out of range")
        }
        let srcLine = srcLines[idx]
        let pattern = #"(?:process\.env|import\.meta\.env|Deno\.env\.get)\s*(?:\.([A-Z][A-Z0-9_]*)|\(\s*['"`]([A-Z][A-Z0-9_]*)['"`]\s*\))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: srcLine, range: NSRange(srcLine.startIndex..., in: srcLine))
        else {
            return Result(ok: false, file: rel, message: "No env access on line \(line)")
        }
        var key: String?
        for g in 1...2 {
            let r = match.range(at: g)
            if r.location != NSNotFound, let swift = Range(r, in: srcLine) {
                key = String(srcLine[swift])
            }
        }
        guard let name = key else {
            return Result(ok: false, file: rel, message: "Could not extract env name on line \(line)")
        }

        let examplePath = (root as NSString).appendingPathComponent(".env.example")
        var existing = (try? String(contentsOfFile: examplePath, encoding: .utf8)) ?? ""
        let already = existing.split(separator: "\n").contains { raw in
            let t = raw.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("\(name)=") || t.hasPrefix("export \(name)=")
        }
        if already {
            return Result(ok: true, file: ".env.example", message: "\(name) already in .env.example")
        }
        if !existing.isEmpty && !existing.hasSuffix("\n") { existing += "\n" }
        existing += "\(name)=\n"
        do {
            try existing.write(toFile: examplePath, atomically: true, encoding: .utf8)
        } catch {
            return Result(ok: false, file: ".env.example", message: error.localizedDescription)
        }
        return Result(
            ok: true,
            file: ".env.example",
            message: "Documented \(name) in .env.example (empty — set the real value on the host)."
        )
    }

    private static func writeLines(_ lines: [String], to abs: String, trailingNewline: Bool) {
        var out = lines.joined(separator: "\n")
        if trailingNewline { out += "\n" }
        try? out.write(toFile: abs, atomically: true, encoding: .utf8)
    }
}
