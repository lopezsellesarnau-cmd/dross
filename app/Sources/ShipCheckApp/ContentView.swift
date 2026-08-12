import SwiftUI

struct ContentView: View {
    // Empty, not $HOME — defaulting to the home directory invites exactly
    // the failure this field's placeholder warns about (scanning a huge
    // non-repo directory). The user must point it at an actual repo.
    @State private var repoPath: String
    @State private var report: ScanReport?
    @State private var errorText: String?
    @State private var scanning = false
    @State private var selectedFinding: Finding?

    var onBack: (() -> Void)? = nil
    var onScanComplete: ((String, ScanReport) -> Void)? = nil

    init(initialPath: String = "", onBack: (() -> Void)? = nil, onScanComplete: ((String, ScanReport) -> Void)? = nil) {
        _repoPath = State(initialValue: initialPath)
        self.onBack = onBack
        self.onScanComplete = onScanComplete
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                Divider().overlay(Theme.inkAlpha(0.22))

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        pathRow
                        if let report {
                            summaryPanel(report)
                            Panel(title: "REPO GRAPH", trailing: "\(report.findings.count) marked") {
                                RepoGraphView(report: report) { finding in
                                    selectedFinding = finding
                                }
                                .frame(height: 260)
                            }
                            if let selectedFinding {
                                CodePreviewView(repoRoot: report.repoRoot, finding: selectedFinding) {
                                    self.selectedFinding = nil
                                }
                                .frame(height: 260)
                            }
                            findingsPanel(report)
                        } else if let errorText {
                            Text(errorText)
                                .font(Theme.monoLabel())
                                .foregroundStyle(Theme.rust)
                        } else {
                            Text("Open a repo from the file browser, or paste a path, then run a scan.")
                                .font(Theme.monoLabel())
                                .foregroundStyle(Theme.inkAlpha(0.5))
                        }
                    }
                    .padding(20)
                }
            }
            .frame(minWidth: 560, minHeight: 520)

            Divider().overlay(Theme.inkAlpha(0.22))

            FileBrowserView(
                rootPath: $repoPath,
                onPickRepo: { path in repoPath = path },
                onPickFile: { path in openFileAsFinding(path) }
            )
        }
        .background(Theme.bone)
        .onAppear {
            // Coming from the home screen with a repo already chosen —
            // scan right away instead of making the user press the button
            // again for a repo they just selected.
            if !repoPath.isEmpty && report == nil && !scanning { runScan() }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button(action: onBack) {
                    Text("‹ REPOS").font(Theme.monoLabel(10.5)).foregroundStyle(Theme.inkAlpha(0.55))
                }
                .buttonStyle(.plain)
            }
            HalftoneMark(accentFraction: markAccentFraction)
                .frame(width: 22, height: 22)
            Text("SHIPCHECK")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Theme.ink)
            Spacer()
            Text("LAUNCH READINESS")
                .font(Theme.monoLabel(10))
                .foregroundStyle(Theme.inkAlpha(0.4))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// The mark's dot cloud reads as the scan's own risk signal, not pure
    /// decoration: no report yet (or a clean one) stays fully ink; the
    /// proportion of findings to files scanned tints that fraction of dots
    /// rust, densest-first — the same "hot spot" logic as the ICON mockups.
    private var markAccentFraction: Double {
        guard let report, report.filesScanned > 0 else { return 0 }
        return min(0.6, Double(report.findings.count) / Double(report.filesScanned) * 3)
    }

    private var pathRow: some View {
        HStack(spacing: 10) {
            TextField("Repo path", text: $repoPath)
                .textFieldStyle(.plain)
                .font(Theme.mono)
                .padding(10)
                .background(Theme.inkAlpha(0.05))
                .overlay(Rectangle().stroke(Theme.inkAlpha(0.25), lineWidth: 1))

            Button(action: runScan) {
                Text(scanning ? "SCANNING…" : "RUN SCAN")
                    .font(Theme.monoLabel(10.5))
                    .tracking(0.8)
                    .foregroundStyle(Theme.bone)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.ink)
            }
            .buttonStyle(.plain)
            .disabled(scanning)
        }
    }

    private func summaryPanel(_ report: ScanReport) -> some View {
        Panel(title: "SUMMARY") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 24) {
                    metric("FILES SCANNED", "\(report.filesScanned)")
                    metric("FINDINGS", "\(report.findings.count)", tone: report.findings.isEmpty ? Theme.ink : Theme.rust)
                    Spacer()
                    Text(report.findings.isEmpty ? "CLEAR TO SHIP" : "REVIEW BEFORE SHIPPING")
                        .font(Theme.monoLabel(10))
                        .tracking(0.6)
                        .foregroundStyle(report.findings.isEmpty ? Theme.inkAlpha(0.55) : Theme.rust)
                }
                if report.truncated {
                    Text("⚠ Stopped early at the file cap — this directory is larger than a single scan covers. Point ShipCheck at a narrower repo path, not a parent folder.")
                        .font(Theme.monoLabel(9.5))
                        .foregroundStyle(Theme.amberWarn)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String, tone: Color = Theme.ink) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.monoLabel(9)).foregroundStyle(Theme.inkAlpha(0.45))
            Text(value).font(.system(size: 20, weight: .medium, design: .monospaced)).foregroundStyle(tone)
        }
    }

    private func findingsPanel(_ report: ScanReport) -> some View {
        Panel(title: "FINDINGS", trailing: "\(report.findings.count)") {
            if report.findings.isEmpty {
                Text("No findings — nothing to review.")
                    .font(Theme.monoLabel(10.5))
                    .foregroundStyle(Theme.inkAlpha(0.5))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(report.findings.enumerated()), id: \.element.id) { index, finding in
                        if index > 0 { Divider().overlay(Theme.inkAlpha(0.12)) }
                        FindingRow(finding: finding, selected: finding.id == selectedFinding?.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedFinding = finding }
                    }
                }
            }
        }
    }

    private func runScan() {
        errorText = nil
        report = nil
        selectedFinding = nil
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try Engine.scan(repoPath: repoPath)
                DispatchQueue.main.async {
                    self.report = result
                    self.scanning = false
                    self.onScanComplete?(self.repoPath, result)
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorText = "Scan failed: \(error.localizedDescription)"
                    self.scanning = false
                }
            }
        }
    }

    /// Clicking a plain file in the browser (not a finding) still opens the
    /// preview — a synthetic zero-line "finding" so the same CodePreviewView
    /// works for "show me this file" as well as "show me what's wrong."
    private func openFileAsFinding(_ absolutePath: String) {
        guard let report else { return }
        let relative = absolutePath.hasPrefix(report.repoRoot)
            ? String(absolutePath.dropFirst(report.repoRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : absolutePath
        selectedFinding = Finding(check: "preview", severity: .info, file: relative, line: 1, message: "Previewing this file — not a finding.")
    }
}

private struct Panel<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(Theme.monoLabel(10)).tracking(1).foregroundStyle(Theme.inkAlpha(0.75))
                Spacer()
                if let trailing {
                    Text(trailing).font(Theme.monoLabel(10)).foregroundStyle(Theme.inkAlpha(0.45))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider().overlay(Theme.inkAlpha(0.18))
            content.padding(14)
        }
        .background(Color.white.opacity(0.35))
        .overlay(Rectangle().stroke(Theme.inkAlpha(0.18), lineWidth: 1))
    }
}

private struct FindingRow: View {
    let finding: Finding
    var selected: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SeverityPill(severity: finding.severity)
            VStack(alignment: .leading, spacing: 3) {
                Text(finding.file)
                    .font(Theme.monoLabel(11))
                    .foregroundStyle(Theme.ink)
                Text(finding.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkAlpha(0.72))
                Text(finding.check.uppercased())
                    .font(Theme.monoLabel(8.5))
                    .foregroundStyle(Theme.inkAlpha(0.35))
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, selected ? 8 : 0)
        .background(selected ? Theme.rust.opacity(0.08) : Color.clear)
    }
}

private struct SeverityPill: View {
    let severity: Severity

    var body: some View {
        Text(severity.rawValue.uppercased())
            .font(Theme.monoLabel(8.5))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(Rectangle().stroke(color, lineWidth: 1))
    }

    private var color: Color {
        switch severity {
        case .finding: return Theme.rust
        case .warning: return Theme.amberWarn
        case .info: return Theme.inkAlpha(0.5)
        }
    }
}
