import SwiftUI
import AppKit

/// Sonar-style quality gate + exportable ship note — under findings.
struct QualityGatePanel: View {
    let report: ScanReport
    var scale: CGFloat = 1
    var onFixSafeExports: (() -> Void)?
    var fixingSafe: Bool = false

    @State private var copied = false

    private func f(_ base: CGFloat) -> CGFloat { base * scale }

    private var driftCount: Int {
        report.openFindings.filter { $0.check == "contract-drift" }.count
    }
    private var demoCount: Int {
        report.openFindings.filter { $0.check == "hardcoded-demo" }.count
    }
    private var hardFindings: Int {
        report.openFindings.filter { $0.severity == .finding }.count
    }
    private var safeExportCount: Int {
        report.openFindings.filter {
            $0.fixHint == .removeExport || $0.fixHint == .deleteDead
        }.count
    }
    private var truncated: Bool { report.truncated }

    private var conditions: [(ok: Bool, label: String)] {
        [
            (!truncated, truncated ? "Scan complete (not truncated)" : "Scan covered the tree"),
            (driftCount == 0, driftCount == 0 ? "No contract drift" : "\(driftCount) contract-drift open"),
            (demoCount == 0, demoCount == 0 ? "No hardcoded demo data" : "\(demoCount) demo-data hits"),
            (hardFindings == 0, hardFindings == 0 ? "No blocking findings" : "\(hardFindings) blocking findings"),
        ]
    }

    private var passed: Bool {
        conditions.allSatisfy(\.ok)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("GATE")
                    .font(.system(size: f(10), weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Theme.bone)
                Spacer()
                Text(passed ? "PASSED" : "FAILED")
                    .font(.system(size: f(10), weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Theme.bone)
            }
            .padding(.horizontal, f(12))
            .padding(.vertical, f(8))
            .background(passed ? Theme.ink : Theme.rust)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(conditions.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Rectangle().fill(Theme.ink).frame(height: 1) }
                    DottedRow(
                        label: row.ok ? "Pass" : "Fail",
                        value: row.label,
                        valueColor: row.ok ? Theme.ink : Theme.rust,
                        scale: scale
                    )
                    .padding(.horizontal, f(12))
                    .padding(.vertical, f(8))
                }
            }
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))

            Text(passed
                 ? "Gate clear — same signal CI quality gates give teams, for a solo pre-deploy."
                 : "Close the FAIL rows before you ship, or copy a ship note for your deploy log.")
                .font(.system(size: f(11), design: .monospaced))
                .foregroundStyle(Theme.inkAlpha(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, f(12))

            HStack(spacing: f(16)) {
                Button(action: copyShipNote) {
                    Text(copied ? "COPIED" : "COPY SHIP NOTE")
                        .font(.system(size: f(10), weight: .medium, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)

                if safeExportCount > 0, let onFixSafeExports {
                    Button(action: onFixSafeExports) {
                        Text(fixingSafe ? "FIXING…" : "FIX \(safeExportCount) VERIFIED")
                            .font(.system(size: f(10), weight: .medium, design: .monospaced))
                            .tracking(1.3)
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(fixingSafe)
                }
            }
            .padding(.top, f(8))
        }
    }

    private func copyShipNote() {
        var body = """
        # Dross ship note
        Repo: \(report.repoRoot)
        Gate: \(passed ? "PASSED" : "FAILED")
        Files: \(report.filesScanned) · Open: \(report.openCount) · Muted: \(report.mutedCount)
        \(report.truncated ? "⚠ Scan truncated\n" : "")
        """
        for c in conditions {
            body += "- [\(c.ok ? "x" : " ")] \(c.label)\n"
        }
        if !report.openFindings.isEmpty {
            body += "\n## Findings\n"
            for finding in report.openFindings {
                let loc = finding.line.map { "\(finding.file):\($0)" } ?? finding.file
                body += "- [\(finding.check)] \(loc) — \(finding.message)\n"
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }
}
