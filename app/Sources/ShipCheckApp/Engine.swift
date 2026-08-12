import Foundation

/// Shells out to the compiled TS engine and parses its `--json` output —
/// this is the actual architecture decision from the vault: engine in
/// TS/Node, UI in native SwiftUI, JSON over stdout as the contract.
///
/// `engineDistPath` is hardcoded to the sibling `dist/cli.js` for now
/// (dev-only convenience — packaging the compiled engine inside the .app
/// bundle is a later step, not done yet).
enum Engine {
    static var enginePath: String {
        let appSourceFile = URL(fileURLWithPath: #filePath)
        // shipcheck/app/Sources/ShipCheckApp/Engine.swift -> shipcheck/dist/cli.js
        return appSourceFile
            .deletingLastPathComponent() // ShipCheckApp/
            .deletingLastPathComponent() // Sources/
            .deletingLastPathComponent() // app/
            .deletingLastPathComponent() // shipcheck/
            .appendingPathComponent("dist/cli.js")
            .path
    }

    struct EngineError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // GUI-launched macOS apps don't inherit the shell's PATH (no .zshrc/nvm
    // setup runs), so `/usr/bin/env node` silently fails to resolve node —
    // that's what caused the original "couldn't be read" JSON error (empty
    // stdout, not actually malformed JSON). Checking known install
    // locations directly sidesteps that; homebrew's is checked first since
    // that's what's installed here.
    static var nodePath: String {
        let candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/env"
    }

    static func scan(repoPath: String) throws -> ScanReport {
        guard FileManager.default.fileExists(atPath: enginePath) else {
            throw EngineError(message: "Engine not found at \(enginePath) — run `npm run build` in the shipcheck repo first.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [enginePath, repoPath, "--json"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        do {
            return try JSONDecoder().decode(ScanReport.self, from: outData)
        } catch {
            let stderrText = String(data: errData, encoding: .utf8) ?? ""
            let stdoutText = String(data: outData, encoding: .utf8) ?? ""
            throw EngineError(message: "Engine produced unparseable output.\nstderr: \(stderrText)\nstdout: \(stdoutText)")
        }
    }
}
