import Foundation
import AppKit

/// Shells out to the compiled TS engine and parses its `--json` output —
/// engine in TS/Node, UI in native SwiftUI, JSON over stdout as the contract.
///
/// Resolution order for the engine:
/// 1. Bundled `Contents/Resources/engine/cli.js` (shipped `.app`)
/// 2. Sibling `dross/dist/cli.js` via `#filePath` (dev checkout)
enum Engine {
    struct EngineError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct FixResult: Codable {
        let ok: Bool
        let file: String
        let message: String
    }

    struct LicenseStatus: Codable {
        let valid: Bool
        let plan: String?
        let email: String?
        let expiresAt: Double?
        let reason: String?
        let source: String?

        static let none = LicenseStatus(valid: false, plan: nil, email: nil, expiresAt: nil, reason: "Not licensed", source: "none")
    }

    /// UserDefaults key for the user's own Anthropic API key (BYO-key model).
    /// Forwarded to the engine only for `scan`; the engine still gates the LLM
    /// pass on a valid license, so a stored key alone unlocks nothing.
    static let anthropicKeyDefaultsKey = "dross.anthropicKey"

    private static func storedAnthropicKey() -> String? {
        let k = UserDefaults.standard.string(forKey: anthropicKeyDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (k?.isEmpty == false) ? k : nil
    }

    /// Hard ceiling so a hung Node process can't leave the UI spinning forever.
    private static let maxRuntime: TimeInterval = 90
    /// Only one Node engine at a time — overlapping Re-scans were racing and
    /// intermittently returning empty stdout / false failures.
    private static let engineLock = NSLock()

    static var enginePath: String {
        if let bundled = Bundle.main.url(forResource: "cli", withExtension: "js", subdirectory: "engine")?.path,
           FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
        // Dev fallback: dross/app/Sources/DrossApp/Engine.swift → dross/dist/cli.js
        let appSourceFile = URL(fileURLWithPath: #filePath)
        return appSourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("dist/cli.js")
            .path
    }

    /// GUI apps don't inherit shell PATH — probe known node installs.
    static var nodePath: String {
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/env"
    }

    static func scan(repoPath: String) throws -> ScanReport {
        // Forward the user's own Anthropic key (if set). The engine runs the
        // LLM pass only when a valid Pro license is also present — so free
        // users never pay the LLM latency, and unlicensed keys unlock nothing.
        var extraEnv: [String: String] = [:]
        if let key = storedAnthropicKey() { extraEnv["ANTHROPIC_API_KEY"] = key }
        let outData = try runEngine(arguments: [enginePath, repoPath, "--json"], extraEnv: extraEnv)
        do {
            return try JSONDecoder().decode(ScanReport.self, from: outData)
        } catch {
            let preview = String(data: outData.prefix(240), encoding: .utf8) ?? "<binary>"
            throw EngineError(message: "Engine produced unparseable scan output.\n\(preview)")
        }
    }

    // MARK: License

    static func licenseStatus() -> LicenseStatus {
        guard let data = try? runEngine(arguments: [enginePath, "license", "--check", "--json"]) else {
            return .none
        }
        return (try? JSONDecoder().decode(LicenseStatus.self, from: data)) ?? .none
    }

    @discardableResult
    static func activateLicense(_ key: String) -> LicenseStatus {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = try? runEngine(arguments: [enginePath, "license", "activate", trimmed, "--json"]),
              let status = try? JSONDecoder().decode(LicenseStatus.self, from: data)
        else {
            return LicenseStatus(valid: false, plan: nil, email: nil, expiresAt: nil, reason: "Could not activate — check the key.", source: nil)
        }
        return status
    }

    static func deactivateLicense() {
        _ = try? runEngine(arguments: [enginePath, "license", "deactivate", "--json"])
    }

    /// Persist a mute in `<repo>/.dross/memory.json` via the CLI.
    static func mute(repoPath: String, file: String, line: Int, reason: String = "Ignored in Dross") throws {
        _ = try runEngine(arguments: [
            enginePath, "mute", repoPath, file, String(line),
            "--reason", reason, "--json",
        ])
    }

    static func unmute(repoPath: String, file: String, line: Int) throws {
        _ = try runEngine(arguments: [enginePath, "unmute", repoPath, file, String(line), "--json"])
    }

    /// Verified autofix: `remove-export` | `delete-dead`.
    /// Runs in-process (Swift) — no Node — so the UI can’t hang on a 90s timeout.
    static func applyVerifiedFix(
        repoPath: String,
        file: String,
        line: Int,
        kind: String
    ) throws -> FixResult {
        let fixer: VerifiedFixer
        switch kind {
        case "delete-dead": fixer = .deleteDead
        default: fixer = .removeExport
        }
        let result = VerifiedFixer.apply(repoPath: repoPath, file: file, line: line, kind: fixer)
        return FixResult(ok: result.ok, file: result.file, message: result.message)
    }

    /// Back-compat alias.
    static func removeExport(repoPath: String, file: String, line: Int) throws -> FixResult {
        try applyVerifiedFix(repoPath: repoPath, file: file, line: line, kind: "remove-export")
    }

    struct VerifyResult {
        let ok: Bool
        let message: String
    }

    /// Post-fix check: `tsc --noEmit` when the repo has TypeScript — proves
    /// the rewrite didn’t break types. Not a guess; compiler is the oracle.
    static func verify(repoPath: String) -> VerifyResult {
        let fm = FileManager.default
        let tsconfig = (repoPath as NSString).appendingPathComponent("tsconfig.json")
        guard fm.fileExists(atPath: tsconfig) else {
            return VerifyResult(ok: true, message: "No tsconfig.json — skipped typecheck. Re-scan still ran.")
        }

        // Global tsc first, repo-local node_modules/.bin/tsc only as a
        // fallback — a repo-local binary is controlled by whatever that
        // repo's package.json pulled in, so preferring it means Dross would
        // execute attacker-controlled code from a repo it's merely scanning,
        // with the user's full permissions and no sandbox (the same failure
        // class as CodeRabbit's 2025 RCE, which ran a target repo's own
        // Rubocop unsandboxed). Low real-world risk today since Dross only
        // opens folders you already trusted enough to run `npm install` on
        // — but cheap to close now, before "scan a repo before you trust it"
        // becomes a real use case.
        let tscCandidates = [
            "/opt/homebrew/bin/tsc",
            "/usr/local/bin/tsc",
            (repoPath as NSString).appendingPathComponent("node_modules/.bin/tsc"),
        ]
        guard let tsc = tscCandidates.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            return VerifyResult(ok: true, message: "TypeScript compiler not found — skipped typecheck. Re-scan still ran.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tsc)
        process.arguments = ["--noEmit", "-p", repoPath]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return VerifyResult(ok: false, message: "Could not run tsc: \(error.localizedDescription)")
        }
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus == 0 {
            return VerifyResult(ok: true, message: "Typecheck passed (tsc --noEmit).")
        }
        let blob = (err + "\n" + out).trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = blob.split(separator: "\n").prefix(6).joined(separator: "\n")
        return VerifyResult(ok: false, message: "Typecheck failed:\n\(clipped)")
    }

    struct CommitResult {
        let ok: Bool
        let message: String
    }

    /// Stage tracked modifications and commit — closes the solo ship loop
    /// after verified fixes. Does not add untracked files (avoids secrets).
    static func commitFixes(repoPath: String) -> CommitResult {
        let git = "/usr/bin/git"
        guard FileManager.default.isExecutableFile(atPath: git) else {
            return CommitResult(ok: false, message: "git not found at /usr/bin/git.")
        }
        let gitDir = (repoPath as NSString).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir) else {
            return CommitResult(ok: false, message: "Not a git repo — open the package root that has .git.")
        }

        let status = runGit(repoPath, ["status", "--porcelain"])
        guard status.ok else {
            return CommitResult(ok: false, message: status.out.isEmpty ? "git status failed." : status.out)
        }
        let dirty = status.out
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard !dirty.isEmpty else {
            return CommitResult(ok: true, message: "Working tree clean — nothing to commit.")
        }

        // Only update already-tracked files (Dross rewrites existing sources).
        let add = runGit(repoPath, ["add", "-u"])
        guard add.ok else {
            return CommitResult(ok: false, message: add.out.isEmpty ? "git add failed." : add.out)
        }

        let commit = runGit(repoPath, [
            "commit",
            "-m", "chore: apply Dross verified fixes",
        ])
        if commit.code == 0 {
            let short = runGit(repoPath, ["rev-parse", "--short", "HEAD"]).out
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let label = short.isEmpty ? "committed" : short
            return CommitResult(ok: true, message: "Committed \(label) — \(dirty.count) change(s).")
        }
        let err = commit.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return CommitResult(ok: false, message: err.isEmpty ? "git commit failed." : err)
    }

    private static func runGit(_ repoPath: String, _ args: [String]) -> (ok: Bool, code: Int32, out: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath] + args
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, -1, error.localizedDescription)
        }
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let blob = (out + err).trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus == 0, process.terminationStatus, blob)
    }

    /// Resolve a finding path against the opened folder, or a sibling package
    /// when the engine prefixed a companion root (`trace-backend/src/…`).
    static func resolveSource(repoPath: String, file: String) -> (root: String, rel: String, abs: String)? {
        let fm = FileManager.default
        let primary = (repoPath as NSString).appendingPathComponent(file)
        if fm.fileExists(atPath: primary) {
            return (repoPath, file, primary)
        }
        let parts = file.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        if parts.count == 2 {
            let parent = (repoPath as NSString).deletingLastPathComponent
            let siblingRoot = (parent as NSString).appendingPathComponent(parts[0])
            let abs = (siblingRoot as NSString).appendingPathComponent(parts[1])
            if fm.fileExists(atPath: abs) {
                return (siblingRoot, parts[1], abs)
            }
        }
        return nil
    }

    /// Open file in VS Code (preferred). Cursor only as fallback, then Finder default.
    static func openInEditor(repoPath: String, file: String, line: Int?) {
        let abs = resolveSource(repoPath: repoPath, file: file)?.abs
            ?? (repoPath as NSString).appendingPathComponent(file)
        let lineSuffix = line.map { ":\($0)" } ?? ""
        let target = abs + lineSuffix

        let editors = [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            "/usr/local/bin/cursor",
            "/opt/homebrew/bin/cursor",
        ]
        for editor in editors where FileManager.default.isExecutableFile(atPath: editor) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: editor)
            p.arguments = ["-g", target]
            try? p.run()
            return
        }
        if FileManager.default.fileExists(atPath: "/Applications/Visual Studio Code.app") {
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: abs)],
                withApplicationAt: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: abs))
    }

    private static func runEngine(arguments: [String], extraEnv: [String: String] = [:]) throws -> Data {
        engineLock.lock()
        defer { engineLock.unlock() }

        guard FileManager.default.fileExists(atPath: enginePath) else {
            throw EngineError(message: "Engine not found at \(enginePath) — run `npm run build` or rebuild the app.")
        }
        guard FileManager.default.isExecutableFile(atPath: nodePath) || nodePath.hasSuffix("/env") else {
            throw EngineError(message: "Node.js not found. Install Node or ensure /opt/homebrew/bin/node exists.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        if nodePath.hasSuffix("/env") {
            process.arguments = ["node"] + arguments
        } else {
            process.arguments = arguments
        }

        var env = ProcessInfo.processInfo.environment
        // Prefer a clean PATH so child scripts resolve the same node.
        if env["PATH"] == nil || env["PATH"]?.isEmpty == true {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
        // Never inherit a shell ANTHROPIC key into GUI scans — an LLM hang
        // looked like a flaky 90s Re-scan timeout. Callers opt in explicitly
        // via extraEnv (scan forwards the user's stored key when set).
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        for (k, v) in extraEnv { env[k] = v }
        process.environment = env

        // Don't inherit the app's stdin — Node can block waiting for it from a GUI.
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Drain pipes on a side queue WHILE the process runs. Waiting in a
        // sleep loop without reading fills the OS pipe buffer (~64KB) and
        // deadlocks Node — that looked like a freeze / resource melt.
        let outBox = PipeBox()
        let errBox = PipeBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outBox.data = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        try process.run()

        // Wait for pipes to EOF (Node closed stdout/stderr). Do NOT treat
        // `process.isRunning` as failure here — after a fast exit the process
        // can still report running for a moment; killing it then looked like
        // “Re-scan always times out.”
        let deadline = DispatchTime.now() + maxRuntime
        let waitResult = group.wait(timeout: deadline)
        if waitResult == .timedOut {
            process.terminate()
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            _ = group.wait(timeout: .now() + 2)
            if process.isRunning { process.interrupt() }
            throw EngineError(message: "Engine timed out after \(Int(maxRuntime))s — try a narrower path.")
        }
        process.waitUntilExit()

        let outData = outBox.data
        let errData = errBox.data
        let stderrText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Exit 1 with JSON is a valid "findings present" scan — only fail hard
        // when there's no parseable stdout.
        if outData.isEmpty {
            throw EngineError(message: "Engine produced no output.\nstderr: \(stderrText.isEmpty ? "(empty)" : stderrText)")
        }

        let status = process.terminationStatus
        // 0 = clean, 1 = findings present (still success for the app)
        if status != 0 && status != 1 {
            let preview = String(data: outData.prefix(200), encoding: .utf8) ?? ""
            if !preview.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                throw EngineError(message: "Engine exited \(status).\nstderr: \(stderrText)\nstdout: \(preview)")
            }
        }

        return outData
    }

    /// Thread-safe bag for pipe drain workers.
    private final class PipeBox: @unchecked Sendable {
        var data = Data()
    }
}
