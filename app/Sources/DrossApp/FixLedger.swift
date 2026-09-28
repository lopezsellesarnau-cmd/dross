import Foundation

/// Every file Dross itself writes this session — auto-correct, Save, bulk
/// fixes. "Commit fixes" commits exactly these and nothing else: a
/// `git add -u` swept up whatever else the user had in progress and
/// committed it under "chore: apply Dross verified fixes".
///
/// Each path also remembers whether it was already dirty in git *before*
/// Dross first touched it. Those are "mixed" — committing them would ship
/// the user's own unfinished edits too — so they're left for the user.
enum FixLedger {
    private static let lock = NSLock()
    /// Absolute path → was the file clean in git before Dross's first write?
    private static var touched: [String: Bool] = [:]

    private static func key(_ abs: String) -> String {
        URL(fileURLWithPath: abs).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Call right BEFORE Dross writes `abs`. Only the first write in a
    /// session records the before-state; later writes (a revert, a second
    /// fix in the same file) keep it.
    static func willWrite(_ abs: String) {
        let k = key(abs)
        lock.lock()
        let seen = touched[k] != nil
        lock.unlock()
        guard !seen else { return }
        let clean = isCleanInGit(k)
        lock.lock()
        if touched[k] == nil { touched[k] = clean }
        lock.unlock()
    }

    /// Files Dross wrote inside `root` (a git toplevel), as paths relative
    /// to it — relative, because macOS paths are case-insensitive but git's
    /// absolute pathspecs aren't (`~/dross` vs a toplevel of `~/Dross`).
    /// Split by whether they're safe to commit on the user's behalf.
    static func entries(inRepo root: String) -> (clean: [String], mixed: [String]) {
        let prefix = key(root) + "/"
        lock.lock()
        let snapshot = touched
        lock.unlock()
        var clean: [String] = []
        var mixed: [String] = []
        for (path, wasClean) in snapshot.sorted(by: { $0.key < $1.key })
        where path.lowercased().hasPrefix(prefix.lowercased()) {
            let rel = String(path.dropFirst(prefix.count))
            if wasClean { clean.append(rel) } else { mixed.append(rel) }
        }
        return (clean, mixed)
    }

    /// Drop committed files (relative to `root`) from the session.
    static func forget(_ rels: [String], inRepo root: String) {
        let prefix = (key(root) + "/").lowercased()
        let targets = Set(rels.map { prefix + $0.lowercased() })
        lock.lock()
        for k in touched.keys where targets.contains(k.lowercased()) { touched.removeValue(forKey: k) }
        lock.unlock()
    }

    /// Clean = no pending change in git for this path (a file that doesn't
    /// exist yet, like a new .env.example, is clean too). Outside a git
    /// repo, git errors → treated as not clean: never commit what we can't
    /// reason about.
    private static func isCleanInGit(_ abs: String) -> Bool {
        let dir = (abs as NSString).deletingLastPathComponent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // Name relative to its own folder — see `entries` on path case.
        process.arguments = ["-C", dir, "status", "--porcelain", "--", (abs as NSString).lastPathComponent]
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return process.terminationStatus == 0 && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
