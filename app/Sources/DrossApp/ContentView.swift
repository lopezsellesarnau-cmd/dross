import SwiftUI
import AppKit

/// Repo detail — industrial layout: hairlines + whitespace, no card box.
/// Sharp corners everywhere except the folder stacks on home.
struct ContentView: View {
    @ObservedObject var store: RepoStore
    var onBack: (() -> Void)? = nil
    /// Open a different folder from detail (home “+ open repo” equivalent).
    var onOpenAnother: ((String) -> Void)? = nil
    var onScanComplete: ((String, ScanReport) -> Void)? = nil

    @State private var repoPath: String
    @State private var report: ScanReport?
    @State private var errorText: String?
    @State private var scanning = false
    /// Bumps on every scan request — stale Node completions are ignored.
    @State private var scanToken: Int = 0
    @State private var selectedFinding: Finding?
    @State private var fixingSafeExports = false
    /// Ordered finding ids for the current fix session (advance after each fix).
    @State private var fixSessionOrder: [String] = []
    @State private var fixSessionCursor: Int = 0
    /// Ids already handled this session (fixed or skipped) — never reopen.
    @State private var fixSessionHandled: Set<String> = []
    @State private var fixSessionDone = false
    @State private var fixSessionAdvancing = false
    @State private var verifying = false
    @State private var verifyMessage: String?
    @State private var committing = false
    @State private var commitMessage: String?
    @State private var showLowConfidence = false
    @State private var showMuted = false

    private let pageBackground = Theme.bone
    private let figmaDesignWidth: CGFloat = 1728

    init(
        store: RepoStore,
        initialPath: String = "",
        onBack: (() -> Void)? = nil,
        onOpenAnother: ((String) -> Void)? = nil,
        onScanComplete: ((String, ScanReport) -> Void)? = nil
    ) {
        self.store = store
        _repoPath = State(initialValue: initialPath)
        self.onBack = onBack
        self.onOpenAnother = onOpenAnother
        self.onScanComplete = onScanComplete
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, max(0.45, geo.size.width / figmaDesignWidth))
            ZStack {
                content(scale: scale)
                if fixSessionDone {
                    FixSessionDonePopup(
                        verifyMessage: verifyMessage,
                        verifying: verifying,
                        commitMessage: commitMessage,
                        committing: committing,
                        onVerify: verifyAfterFixes,
                        onCommit: commitFixes,
                        onClose: {
                            fixSessionDone = false
                            verifyMessage = nil
                            commitMessage = nil
                        }
                    )
                } else if let selectedFinding {
                    CodeFixPopup(
                        // Always the folder the user opened — not report.repoRoot
                        // (multi-package scans label that as "app + backend").
                        repoRoot: repoPath,
                        finding: selectedFinding,
                        queuePosition: min(fixSessionCursor + 1, max(fixSessionOrder.count, 1)),
                        queueTotal: max(fixSessionOrder.count, 1),
                        onClose: {
                            self.selectedFinding = nil
                            self.fixSessionOrder = []
                        },
                        onOpenEditor: { finding in
                            Engine.openInEditor(
                                repoPath: repoPath,
                                file: finding.file,
                                line: finding.line
                            )
                        },
                        onFixedAndAdvance: { advanceFixSession(afterFix: true) },
                        onSkipToNext: { advanceFixSession(afterFix: false) },
                        onMute: { muteFinding($0) },
                        isAdvancing: fixSessionAdvancing
                    )
                }
            }
        }
        .background(PageGrain())
        .frame(minWidth: 980, minHeight: 700)
        .onAppear {
            guard !repoPath.isEmpty, report == nil, !scanning else { return }
            if let cached = store.report(for: repoPath) {
                report = cached
                // Don't auto-open the popup — user picks a finding or FIX NOW.
                selectedFinding = nil
            } else {
                runScan()
            }
        }
    }

    private func content(scale: CGFloat) -> some View {
        func f(_ base: CGFloat) -> CGFloat { base * scale }

        return VStack(alignment: .leading, spacing: 0) {
            CheckerStrip(cell: f(7))
            datasheetMeta(f: f, scale: scale)
            Rectangle().fill(Theme.ink).frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                SpineLabel(text: "Pre-deploy scan", scale: scale)
                    .frame(width: f(36))
                    .frame(maxHeight: .infinity)
                    .background(Theme.bone)
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.ink).frame(width: 1) }

                PreviewsSidebar(
                    store: store,
                    repos: store.repos,
                    scale: scale,
                    selectedPath: repoPath,
                    pageBackground: pageBackground,
                    onSelectRepo: { repo in
                        repoPath = repo.path
                        if let cached = store.report(for: repo.path) {
                            report = cached
                            selectedFinding = nil
                        } else {
                            runScan()
                        }
                    }
                )
                .frame(width: f(240))

                Rectangle().fill(Theme.ink).frame(width: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let report {
                            datasheetHero(report, f: f)
                                .padding(.bottom, f(22))
                            detailContent(report, scale: scale, f: f)
                        } else if let errorText {
                            VStack(alignment: .leading, spacing: f(14)) {
                                Text("SCAN FAILED")
                                    .font(Theme.sectionLabel(f(11)))
                                    .tracking(1.2)
                                    .foregroundStyle(Theme.rust)
                                Text(errorText)
                                    .font(.system(size: f(13), design: .monospaced))
                                    .foregroundStyle(Theme.inkAlpha(0.7))
                                    .textSelection(.enabled)
                                Button(action: runScan) {
                                    Text("RETRY SCAN")
                                        .font(.system(size: f(11), weight: .medium, design: .monospaced))
                                        .tracking(1.2)
                                        .foregroundStyle(pageBackground)
                                        .padding(.horizontal, f(14))
                                        .padding(.vertical, f(8))
                                        .background(Theme.ink)
                                }
                                .buttonStyle(.plain)
                                .disabled(scanning)
                            }
                        } else {
                            Text(scanning ? "SCANNING…" : "WAITING FOR SCAN…")
                                .font(.system(size: f(28), weight: .bold, design: .default))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.leading, f(28))
                    .padding(.trailing, f(28))
                    .padding(.top, f(24))
                    .padding(.bottom, f(28))
                }
                .hideScrollChrome()

                Rectangle().fill(Theme.ink).frame(width: 1)

                HStack(alignment: .top, spacing: 0) {
                    ShipAssistRail(
                        report: report,
                        scanning: scanning,
                        scale: scale,
                        onRescan: runScan,
                        onFixNow: fixNow
                    )
                    .frame(width: f(220))
                    SpineLabel(text: "Limitations: none registered", scale: scale)
                        .frame(width: f(28))
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Datasheet chrome

    private func datasheetMeta(f: (CGFloat) -> CGFloat, scale: CGFloat) -> some View {
        let name = (repoPath as NSString).lastPathComponent
        let open = report?.openCount ?? 0
        return HStack(spacing: f(16)) {
            if let onBack {
                Button(action: onBack) {
                    Text("← REPOS")
                        .font(.system(size: f(11), weight: .medium, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Theme.bone)
                        .padding(.horizontal, f(12))
                        .padding(.vertical, f(7))
                        .background(Theme.ink)
                }
                .buttonStyle(.plain)
                .help("Back to repos")
            }
            Text("TYPE: REPO / PRE-DEPLOY")
                .font(.system(size: f(10), weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
            Text("·")
                .foregroundStyle(Theme.inkAlpha(0.35))
            Text(name.isEmpty ? "—" : name.uppercased())
                .font(.system(size: f(10), weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: f(8))
            if scanning {
                Text("SCANNING")
                    .font(.system(size: f(10), weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Theme.inkAlpha(0.45))
            }
            InkBadge(
                text: report == nil ? "STANDBY" : (open == 0 ? "CLEAR TO SHIP" : "REVIEW"),
                alert: report != nil && open > 0,
                scale: scale
            )
            if onOpenAnother != nil {
                Button(action: { RepoPicker.present { path in onOpenAnother?(path) } }) {
                    Text("OPEN")
                        .font(.system(size: f(10), weight: .medium, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .disabled(scanning)
            }
            Button(action: runScan) {
                Text("RE-SCAN")
                    .font(.system(size: f(10), weight: .medium, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
            .disabled(scanning || repoPath.isEmpty)
        }
        .padding(.horizontal, f(16))
        .padding(.vertical, f(12))
    }

    private func datasheetHero(_ report: ScanReport, f: (CGFloat) -> CGFloat) -> some View {
        let open = report.openCount
        let serial = String((repoPath as NSString).lastPathComponent.uppercased().prefix(12))
        return VStack(alignment: .leading, spacing: f(14)) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: f(10)) {
                    Text(open == 0 ? "Clear to ship." : "Review before ship.")
                        .font(.system(size: f(36), weight: .bold, design: .default))
                        .tracking(-0.8)
                        .foregroundStyle(Theme.ink)
                    Text("SCAN / FIX / VERIFY / COMMIT")
                        .font(.system(size: f(11), weight: .medium, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(Theme.inkAlpha(0.55))
                    Text(">>>>>>>>>>>>>>>>")
                        .font(.system(size: f(11), weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                    Text("Last pass before main. Deterministic checks, local memory, no cloud.")
                        .font(.system(size: f(11), design: .monospaced))
                        .foregroundStyle(Theme.inkAlpha(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: f(16))
                VStack(alignment: .trailing, spacing: f(6)) {
                    HalftoneMark(accentFraction: markAccentFraction)
                        .frame(width: f(56), height: f(64))
                    Text("SERIAL: \(serial)")
                        .font(.system(size: f(10), weight: .medium, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(Theme.ink)
                    Text("STATUS: \(open == 0 ? "IN CLEAR" : "IN REVIEW")")
                        .font(.system(size: f(10), weight: .medium, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(open == 0 ? Theme.ink : Theme.rust)
                    Text("FILES: \(report.filesScanned)  OPEN: \(open)")
                        .font(.system(size: f(10), weight: .medium, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(Theme.ink)
                }
            }
            HatchBar(
                filled: min(open, 16),
                total: 16,
                color: open == 0 ? Theme.ink : Theme.rust,
                height: f(8)
            )
        }
    }

    private var markAccentFraction: Double {
        guard let report, report.filesScanned > 0 else { return 0 }
        return min(0.6, Double(report.openCount) / Double(report.filesScanned) * 3)
    }

    // MARK: Detail

    private func detailContent(_ report: ScanReport, scale: CGFloat, f: @escaping (CGFloat) -> CGFloat) -> some View {
        VStack(alignment: .leading, spacing: f(28)) {
            findingsList(report, f: f)

            if report.truncated {
                Text("Stopped early at the file cap — point Dross at a narrower repo path.")
                    .font(.system(size: f(11), design: .monospaced))
                    .foregroundStyle(Theme.inkAlpha(0.5))
            }

            QualityGatePanel(
                report: report,
                scale: scale,
                onFixSafeExports: fixAllSafeExports,
                fixingSafe: fixingSafeExports
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func visibleFindings(in report: ScanReport) -> [Finding] {
        report.findings.filter { finding in
            if finding.muted { return showMuted }
            if finding.confidence == .low { return showLowConfidence }
            return true
        }
        .sorted { a, b in
            let rank: (Confidence) -> Int = { $0 == .high ? 0 : $0 == .medium ? 1 : 2 }
            if rank(a.confidence) != rank(b.confidence) { return rank(a.confidence) < rank(b.confidence) }
            if a.isRecurring != b.isRecurring { return a.isRecurring && !b.isRecurring }
            return a.file < b.file
        }
    }

    private func findingsList(_ report: ScanReport, f: @escaping (CGFloat) -> CGFloat) -> some View {
        let visible = visibleFindings(in: report)
        let hiddenLow = report.openFindings.filter { $0.confidence == .low }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: f(12)) {
                Text("SPEC")
                    .font(.system(size: f(10), weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Theme.bone)
                Spacer()
                Text("\(visible.count) ROWS")
                    .font(.system(size: f(10), weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.bone.opacity(0.7))
                if hiddenLow > 0 {
                    Button { showLowConfidence.toggle() } label: {
                        Text(showLowConfidence ? "HIDE LOW" : "\(hiddenLow) LOW")
                            .font(.system(size: f(10), weight: .medium, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(Theme.bone)
                    }
                    .buttonStyle(.plain)
                }
                if report.mutedCount > 0 {
                    Button { showMuted.toggle() } label: {
                        Text(showMuted ? "HIDE MUTED" : "\(report.mutedCount) MUTED")
                            .font(.system(size: f(10), weight: .medium, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(Theme.bone)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, f(12))
            .padding(.vertical, f(8))
            .background(Theme.ink)

            HStack(spacing: 0) {
                specCol("CHECK", f: f).frame(width: f(120), alignment: .leading)
                specCol("FILE", f: f).frame(maxWidth: .infinity, alignment: .leading)
                specCol("SIGNAL", f: f).frame(width: f(88), alignment: .trailing)
            }
            .padding(.horizontal, f(12))
            .padding(.vertical, f(6))
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))

            if visible.isEmpty {
                Text(report.openCount == 0
                     ? (report.mutedCount > 0 ? "No open findings — muted items stay in memory." : "No findings — nothing to review.")
                     : "No high-confidence findings. Show low to review weaker signals.")
                    .font(.system(size: f(11), design: .monospaced))
                    .foregroundStyle(Theme.inkAlpha(0.5))
                    .padding(f(14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, finding in
                        if index > 0 { Rectangle().fill(Theme.ink).frame(height: 1) }
                        findingRow(finding, f: f)
                    }
                }
                .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
            }
        }
    }

    private func specCol(_ title: String, f: (CGFloat) -> CGFloat) -> some View {
        Text(title)
            .font(.system(size: f(9.5), weight: .medium, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(Theme.inkAlpha(0.45))
    }

    private func findingRow(_ finding: Finding, f: @escaping (CGFloat) -> CGFloat) -> some View {
        Button {
            if let report { beginFixSession(at: finding, in: report) }
        } label: {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: f(3)) {
                    Text(finding.check.replacingOccurrences(of: "-", with: " ").uppercased())
                        .font(.system(size: f(10), weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Theme.ink)
                    if finding.isRecurring {
                        Text("↻ REGRESSION")
                            .font(.system(size: f(9), weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.rust)
                    }
                }
                .frame(width: f(120), alignment: .leading)

                VStack(alignment: .leading, spacing: f(3)) {
                    Text(findingLineLabel(finding))
                        .font(.system(size: f(11), weight: .medium, design: .monospaced))
                        .foregroundStyle(selectedFinding?.id == finding.id ? Theme.rust : Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(finding.message)
                        .font(.system(size: f(11), design: .monospaced))
                        .foregroundStyle(Theme.inkAlpha(0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: f(3)) {
                    Text(finding.confidence.rawValue.uppercased())
                        .font(.system(size: f(10), weight: .medium, design: .monospaced))
                        .foregroundStyle(finding.confidence == .high ? Theme.rust : Theme.ink)
                    Text(VerifiedFixer.fixer(for: finding) != nil ? "AUTO" : "EDIT")
                        .font(.system(size: f(9), weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.inkAlpha(0.4))
                    if finding.muted {
                        Text("MUTED")
                            .font(.system(size: f(9), weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.inkAlpha(0.4))
                    }
                }
                .frame(width: f(88), alignment: .trailing)
            }
            .padding(.horizontal, f(12))
            .padding(.vertical, f(10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(finding.muted ? 0.5 : 1)
    }

    private func findingLineLabel(_ finding: Finding) -> String {
        if let line = finding.line {
            return "\(finding.file):\(line)"
        }
        return finding.file
    }

    private func fixNow() {
        guard let report else { return }
        let queue = visibleFindings(in: report).filter { !$0.muted }
        guard !queue.isEmpty else { return }
        let start = queue.first(where: { VerifiedFixer.fixer(for: $0) != nil }) ?? queue[0]
        beginFixSession(at: start, in: report)
    }

    private func beginFixSession(at finding: Finding, in report: ScanReport) {
        fixSessionDone = false
        verifyMessage = nil
        fixSessionHandled = []
        fixSessionAdvancing = false
        let queue = visibleFindings(in: report).filter { !$0.muted }
        fixSessionOrder = queue.map(\.id)
        fixSessionCursor = fixSessionOrder.firstIndex(of: finding.id) ?? 0
        selectedFinding = finding
    }

    private func muteFinding(_ finding: Finding) {
        guard let line = finding.line else { return }
        let path = repoPath
        let file = finding.file
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try Engine.mute(repoPath: path, file: file, line: line)
                DispatchQueue.main.async {
                    self.selectedFinding = nil
                    self.fixSessionOrder = []
                    self.runScan()
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorText = "Mute failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Advance the fix queue WITHOUT a full engine scan.
    ///
    /// Save & next used to call `Engine.scan` on every step. That spawned a
    /// Node process per click, could stack concurrent scans, and with a pipe
    /// deadlock in Engine looked like a freeze / crash. Navigation is local;
    /// the heavy re-scan happens once on "Re-scan & verify" when the queue ends.
    private func advanceFixSession(afterFix: Bool) {
        guard !fixSessionAdvancing else { return }
        fixSessionAdvancing = true
        defer { fixSessionAdvancing = false }

        if let current = selectedFinding {
            fixSessionHandled.insert(current.id)
        }

        guard let report else {
            selectedFinding = nil
            fixSessionDone = true
            return
        }

        // Prefer the live report list (same order) for the next unhandled id.
        let byId = Dictionary(uniqueKeysWithValues: report.findings.map { ($0.id, $0) })

        var next = fixSessionCursor + 1
        while next < fixSessionOrder.count {
            let id = fixSessionOrder[next]
            if !fixSessionHandled.contains(id), let finding = byId[id] {
                fixSessionCursor = next
                selectedFinding = finding
                return
            }
            next += 1
        }

        // Anything left earlier in the queue?
        if let remainId = fixSessionOrder.first(where: { !fixSessionHandled.contains($0) && byId[$0] != nil }),
           let finding = byId[remainId],
           let idx = fixSessionOrder.firstIndex(of: remainId) {
            fixSessionCursor = idx
            selectedFinding = finding
            return
        }

        selectedFinding = nil
        fixSessionDone = true
    }

    private func verifyAfterFixes() {
        verifying = true
        verifyMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try Engine.scan(repoPath: self.repoPath)
                let compile = Engine.verify(repoPath: self.repoPath)
                DispatchQueue.main.async {
                    self.report = result
                    self.onScanComplete?(self.repoPath, result)
                    self.verifying = false
                    let scanLine = result.openCount == 0
                        ? "Re-scan: clear — 0 open findings."
                        : "Re-scan: \(result.openCount) open finding(s) remain."
                    let compileLine = compile.ok
                        ? compile.message
                        : "Typecheck failed (repo syntax/types — not a Dross crash):\n\(compile.message)"
                    self.verifyMessage = scanLine + "\n" + compileLine
                }
            } catch {
                DispatchQueue.main.async {
                    self.verifying = false
                    self.verifyMessage = "Verify failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func commitFixes() {
        committing = true
        commitMessage = nil
        let path = repoPath
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Engine.commitFixes(repoPath: path)
            DispatchQueue.main.async {
                self.committing = false
                self.commitMessage = result.message
            }
        }
    }

    /// Batch-apply remove-export via engine (quality-gate action). Bottom-up by line
    /// so earlier edits don't shift later line numbers in the same file.
    private func fixAllSafeExports() {
        guard let findings = report?.openFindings.filter({
            ($0.fixHint == .removeExport || $0.fixHint == .deleteDead || $0.fixHint == .addEnvExample) && $0.line != nil
        }), !findings.isEmpty else { return }
        let ordered = findings.sorted { a, b in
            if a.file != b.file { return a.file < b.file }
            return (a.line ?? 0) > (b.line ?? 0)
        }
        fixingSafeExports = true
        errorText = nil
        DispatchQueue.global(qos: .userInitiated).async {
            var failures: [String] = []
            for finding in ordered {
                guard let line = finding.line,
                      let kind = VerifiedFixer.fixer(for: finding)?.cliKind else { continue }
                do {
                    let result = try Engine.applyVerifiedFix(
                        repoPath: self.repoPath, file: finding.file, line: line, kind: kind
                    )
                    if !result.ok { failures.append("\(finding.file):\(line) — \(result.message)") }
                } catch {
                    failures.append("\(finding.file):\(line) — \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                self.fixingSafeExports = false
                if !failures.isEmpty {
                    self.errorText = "Some fixes failed:\n" + failures.prefix(3).joined(separator: "\n")
                }
                self.selectedFinding = nil
                self.runScan()
            }
        }
    }

    private func runScan() {
        errorText = nil
        report = nil
        selectedFinding = nil
        scanning = true
        scanToken += 1
        let token = scanToken
        let path = repoPath
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try Engine.scan(repoPath: path)
                DispatchQueue.main.async {
                    // Newer Re-scan wins — still clear the spinner if we're stale.
                    guard token == self.scanToken else { return }
                    self.report = result
                    self.scanning = false
                    self.selectedFinding = nil
                    self.errorText = nil
                    self.onScanComplete?(path, result)
                }
            } catch {
                DispatchQueue.main.async {
                    guard token == self.scanToken else { return }
                    self.errorText = "Scan failed: \(error.localizedDescription)"
                    self.scanning = false
                }
            }
        }
    }

}
