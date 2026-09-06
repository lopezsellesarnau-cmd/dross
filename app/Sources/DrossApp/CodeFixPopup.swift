import SwiftUI
import AppKit

/// Fix session panel — auto-correct verified findings, then advance.
/// Manual edit/Save for everything else. Done state → verify re-scan.
struct CodeFixPopup: View {
    let repoRoot: String
    let finding: Finding
    let queuePosition: Int
    let queueTotal: Int
    var onClose: () -> Void
    var onOpenEditor: ((Finding) -> Void)? = nil
    var onFixedAndAdvance: (() -> Void)? = nil
    var onSkipToNext: (() -> Void)? = nil
    var onMute: ((Finding) -> Void)? = nil
    var isAdvancing: Bool = false

    private let panelW: CGFloat = 460
    private let panelH: CGFloat = 500
    private let pageBackground = Theme.bone
    private let contextLines = 8

    @State private var draft = ""
    @State private var rangeStart = 1
    @State private var rangeEnd = 1
    @State private var loadFailed = false
    @State private var status: String?
    @State private var dirty = false
    @State private var applying = false

    private var verified: VerifiedFixer? { VerifiedFixer.fixer(for: finding) }

    private var filePath: String {
        Engine.resolveSource(repoPath: repoRoot, file: finding.file)?.abs
            ?? (repoRoot as NSString).appendingPathComponent(finding.file)
    }

    var body: some View {
        GeometryReader { geo in
            let origin = CGPoint(
                x: geo.size.width - panelW - 36,
                y: geo.size.height - panelH - 40
            )

            VStack(spacing: 0) {
                header
                Rectangle().fill(Theme.hair).frame(height: 1)
                meta
                Rectangle().fill(Theme.hair).frame(height: 1)
                editor
                Rectangle().fill(Theme.hair).frame(height: 1)
                footer
            }
            .frame(width: panelW, height: panelH, alignment: .top)
            .background(pageBackground)
            .overlay(Rectangle().stroke(Theme.inkAlpha(0.28), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
            .position(x: origin.x + panelW / 2, y: origin.y + panelH / 2)
        }
        .allowsHitTesting(true)
        .onExitCommand(perform: onClose)
        .onAppear(perform: loadSlice)
        .onChange(of: finding.id) { _, _ in loadSlice() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.rust)
                .frame(width: 6, height: 6)
            Text("Fix session")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
            Text("\(queuePosition)/\(max(queueTotal, 1))")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.inkAlpha(0.4))
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkAlpha(0.45))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(finding.file)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Text(finding.confidence.rawValue.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(finding.confidence == .high ? Theme.rust : Theme.inkAlpha(0.45))
                if finding.isRecurring {
                    Text("↻ regression")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.rust)
                }
                if finding.timesSeen > 1 {
                    Text("seen \(finding.timesSeen)×")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkAlpha(0.4))
                }
            }
            Text(finding.message)
                .font(.system(size: 11, design: .default))
                .foregroundStyle(Theme.inkAlpha(0.55))
                .fixedSize(horizontal: false, vertical: true)
            if let note = finding.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 11, design: .default))
                    .foregroundStyle(Theme.inkAlpha(0.45))
            }

            if let verified {
                Text(verified.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                Text(verified.detail)
                    .font(.system(size: 10, design: .default))
                    .foregroundStyle(Theme.inkAlpha(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Manual only · no verified autofix")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.inkAlpha(0.5))
                Text("We don’t guess patches for this check. Edit + Save, or Skip.")
                    .font(.system(size: 10, design: .default))
                    .foregroundStyle(Theme.inkAlpha(0.42))
            }

            if let status {
                Text(status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.rust)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private let editorFontSize: CGFloat = 11.5

    private var editor: some View {
        Group {
            if loadFailed {
                Text("Couldn't read this file from disk.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.inkAlpha(0.45))
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Lines \(rangeStart)–\(rangeEnd)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.inkAlpha(0.4))
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    LineNumberTextEditor(
                        text: $draft,
                        startLine: rangeStart,
                        fontSize: editorFontSize,
                        textColor: NSColor(Theme.ink),
                        gutterColor: NSColor(Theme.inkAlpha(0.4)),
                        backgroundColor: NSColor(pageBackground)
                    )
                    .padding(.horizontal, 6)
                    .onChange(of: draft) { _, _ in
                        dirty = true
                        status = nil
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: { onSkipToNext?() }) {
                Text("Skip")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.inkAlpha(0.5))
                    .underline(color: Theme.inkAlpha(0.22))
            }
            .buttonStyle(.plain)
            .disabled(isAdvancing || applying)

            Button(action: { onMute?(finding) }) {
                Text("Ignore")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.inkAlpha(0.5))
                    .underline(color: Theme.inkAlpha(0.22))
            }
            .buttonStyle(.plain)
            .disabled(isAdvancing || applying || finding.line == nil)
            .help("Mute this finding in .dross/memory.json — CI won’t fail on it")

            Button(action: { onOpenEditor?(finding) }) {
                Text("VS Code")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.inkAlpha(0.5))
                    .underline(color: Theme.inkAlpha(0.22))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Button(action: { saveSlice(advance: true) }) {
                Text(dirty ? "Save & next" : "Save")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(dirty ? pageBackground : Theme.inkAlpha(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(dirty ? Theme.ink : Theme.inkAlpha(0.08))
            }
            .buttonStyle(.plain)
            .disabled(!dirty || loadFailed || applying || isAdvancing)

            if verified != nil {
                Button(action: autoCorrect) {
                    Text(applying || isAdvancing ? "…" : "Auto-correct")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(pageBackground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.ink)
                }
                .buttonStyle(.plain)
                .disabled(applying || loadFailed || isAdvancing)
                .help("Apply the verified rewrite, then open the next finding")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func loadSlice() {
        status = nil
        dirty = false
        applying = false
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            loadFailed = true
            draft = ""
            return
        }
        loadFailed = false
        let allLines = content.components(separatedBy: "\n")
        let target = finding.line ?? 1
        rangeStart = max(1, target - contextLines)
        rangeEnd = min(allLines.count, target + contextLines)
        guard rangeStart <= rangeEnd else {
            draft = ""
            return
        }
        draft = allLines[(rangeStart - 1)..<rangeEnd].joined(separator: "\n")
    }

    private func autoCorrect() {
        guard let verified, let line = finding.line else { return }
        applying = true
        status = "Applying verified fix…"
        let kind = verified.cliKind
        let root = repoRoot
        let file = finding.file
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // resolveSource inside applyVerifiedFix handles companion paths
                let result = try Engine.applyVerifiedFix(
                    repoPath: root, file: file, line: line, kind: kind
                )
                guard result.ok else {
                    DispatchQueue.main.async {
                        self.applying = false
                        self.status = result.message
                    }
                    return
                }
                // Proof, not trust: a deterministic rewrite can still be
                // syntactically valid but semantically wrong (e.g. the wrong
                // block matched a brace-balance edge case) — tsc is the
                // oracle that catches that before the user moves on to the
                // next finding believing this one is actually safe.
                self.verifyAndFinish(baseMessage: result.message, root: root)
            } catch {
                DispatchQueue.main.async {
                    self.applying = false
                    self.status = error.localizedDescription
                }
            }
        }
    }

    /// Runs `tsc --noEmit` after a fix lands and only advances to the next
    /// finding if it still passes — a failed typecheck stays on screen so
    /// the user sees what broke instead of the popup moving on as if
    /// nothing happened. Always off the main thread; `Engine.verify` shells
    /// out to a real compiler process, which blocks.
    private func verifyAndFinish(baseMessage: String, root: String, advanceOnSuccess: Bool = true) {
        DispatchQueue.main.async { self.status = baseMessage + "\nVerifying…" }
        let verify = Engine.verify(repoPath: root)
        DispatchQueue.main.async {
            self.applying = false
            self.status = baseMessage + "\n" + (verify.ok ? "✓ \(verify.message)" : "✗ \(verify.message)")
            self.dirty = false
            if verify.ok && advanceOnSuccess {
                self.onFixedAndAdvance?()
            }
        }
    }

    private func saveSlice(advance: Bool) {
        applying = true
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            status = "Couldn't read file to save."
            applying = false
            return
        }
        var allLines = content.components(separatedBy: "\n")
        let newLines = draft.components(separatedBy: "\n")
        let startIdx = rangeStart - 1
        let endIdx = rangeEnd
        guard startIdx >= 0, endIdx <= allLines.count, startIdx < endIdx else {
            status = "Line range out of date — reopen."
            applying = false
            return
        }
        allLines.replaceSubrange(startIdx..<endIdx, with: newLines)
        do {
            try allLines.joined(separator: "\n").write(toFile: filePath, atomically: true, encoding: .utf8)
            rangeEnd = rangeStart + newLines.count - 1
            let root = repoRoot
            // Same "proof, not trust" step as autoCorrect — a manual edit is
            // exactly the case most likely to introduce a real typo, so it's
            // the one that most needs the compiler to check it before the
            // popup tells the user it's fine.
            DispatchQueue.global(qos: .userInitiated).async {
                self.verifyAndFinish(baseMessage: "Saved to disk.", root: root, advanceOnSuccess: advance)
            }
        } catch {
            status = "Save failed: \(error.localizedDescription)"
            applying = false
        }
    }
}

struct FixSessionDonePopup: View {
    var verifyMessage: String?
    var verifying: Bool
    var commitMessage: String?
    var committing: Bool
    var onVerify: () -> Void
    var onCommit: () -> Void
    var onClose: () -> Void

    private let pageBackground = Theme.bone

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = 400
            let h: CGFloat = 300
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Queue clear")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.inkAlpha(0.45))
                    }
                    .buttonStyle(.plain)
                }
                Text("Verify the writes, then commit tracked fixes so the ship loop closes on this Mac.")
                    .font(.system(size: 12, design: .default))
                    .foregroundStyle(Theme.inkAlpha(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                if let verifyMessage {
                    Text(verifyMessage)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.inkAlpha(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let commitMessage {
                    Text(commitMessage)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.inkAlpha(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(action: onVerify) {
                    Text(verifying ? "Verifying…" : "Re-scan & verify")
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(pageBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.ink)
                }
                .buttonStyle(.plain)
                .disabled(verifying || committing)

                Button(action: onCommit) {
                    Text(committing ? "Committing…" : "Commit fixes")
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(Rectangle().stroke(Theme.inkAlpha(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(verifying || committing)
                .help("git add -u && commit — tracked files only, no untracked secrets")
            }
            .padding(18)
            .frame(width: w, height: h, alignment: .top)
            .background(pageBackground)
            .overlay(Rectangle().stroke(Theme.inkAlpha(0.28), lineWidth: 1))
            .position(x: geo.size.width - w / 2 - 36, y: geo.size.height - h / 2 - 40)
        }
        .allowsHitTesting(true)
    }
}
