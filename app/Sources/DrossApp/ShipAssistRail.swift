import SwiftUI

/// Right-rail UX for the repo detail — fills the empty column with a
/// pre-deploy assist: readiness by check, a short guide (why Dross vs PR
/// bots), and keyboard shortcuts. Aimed at the solo builder who ships
/// without a review ritual (the gap vs CodeRabbit / team CI tools).
struct ShipAssistRail: View {
    let report: ScanReport?
    let scanning: Bool
    var scale: CGFloat = 1
    var onRescan: () -> Void
    var onFixNow: () -> Void

    private func f(_ base: CGFloat) -> CGFloat { base * scale }

    private static let checkOrder = [
        "contract-drift",
        "env-drift",
        "dead-exports",
        "todo-density",
        "hardcoded-demo",
    ]

    private static let checkBlurb: [String: String] = [
        "contract-drift": "Routes, HTTP methods, and auth headers — app ↔ API agreement.",
        "env-drift": "process.env used in code but missing from .env.example — deploy bombs.",
        "dead-exports": "Unused exports — strip keyword or delete the dead block.",
        "todo-density": "Clusters of unfinished markers about to ship.",
        "hardcoded-demo": "Placeholder names, lorem, fake stamps that look real.",
    ]

    private var counts: [String: Int] {
        guard let report else { return [:] }
        var map: [String: Int] = [:]
        for finding in report.openFindings {
            map[finding.check, default: 0] += 1
        }
        return map
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            readinessHeader
            Rectangle().fill(Theme.hair).frame(height: 1)
                .padding(.vertical, f(16))
            checksBlock
            Rectangle().fill(Theme.hair).frame(height: 1)
                .padding(.vertical, f(16))
            memoryBlock
            Rectangle().fill(Theme.hair).frame(height: 1)
                .padding(.vertical, f(16))
            guideBlock
            Rectangle().fill(Theme.hair).frame(height: 1)
                .padding(.vertical, f(16))
            shortcutsBlock
            Spacer(minLength: 0)
            if report != nil {
                actions
            }
        }
        .padding(.leading, f(22))
        .padding(.trailing, f(4))
        .padding(.top, f(4))
        .padding(.bottom, f(36))
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var readinessHeader: some View {
        VStack(alignment: .leading, spacing: f(10)) {
            SpecEyebrow(title: "Before you ship", extra: scanning ? "…" : nil, scale: scale)

            if scanning {
                Text("Scanning…")
                    .font(.system(size: f(16), weight: .semibold, design: .default))
                    .foregroundStyle(Theme.inkAlpha(0.45))
            } else if let report {
                let n = report.openCount
                HStack(alignment: .firstTextBaseline, spacing: f(8)) {
                    Circle()
                        .fill(n == 0 ? Theme.inkAlpha(0.28) : Theme.rust)
                        .frame(width: f(8), height: f(8))
                        .offset(y: -1)
                    Text(n == 0 ? "Clear to ship" : "\(n) open")
                        .font(.system(size: f(22), weight: .light, design: .default))
                        .tracking(-0.6)
                        .foregroundStyle(n == 0 ? Theme.ink : Theme.rust)
                        .monospacedDigit()
                }
                Text(report.llmUsed == true
                     ? "Deterministic + LLM drift pass"
                     : "Local deterministic checks")
                    .font(.system(size: f(11), design: .default))
                    .foregroundStyle(Theme.inkAlpha(0.42))
            } else {
                Text("Waiting for scan")
                    .font(.system(size: f(16), weight: .semibold, design: .default))
                    .foregroundStyle(Theme.inkAlpha(0.4))
            }
        }
    }

    private var checksBlock: some View {
        VStack(alignment: .leading, spacing: f(12)) {
            SpecEyebrow(title: "Checks", extra: nil, scale: scale)

            ForEach(Self.checkOrder, id: \.self) { key in
                let count = counts[key] ?? 0
                DottedRow(
                    label: displayName(key),
                    value: count > 0 ? "\(count)" : "—",
                    valueColor: count > 0 ? Theme.rust : Theme.inkAlpha(0.35),
                    scale: scale
                )
            }
        }
    }

    private var memoryBlock: some View {
        VStack(alignment: .leading, spacing: f(8)) {
            SpecEyebrow(title: "Memory", extra: nil, scale: scale)
            if let report {
                let muted = report.mutedCount
                let recurring = report.openFindings.filter(\.isRecurring).count
                Text(muted == 0 && recurring == 0
                     ? "This Mac remembers mutes and regressions in .dross/memory.json."
                     : [
                        muted > 0 ? "\(muted) muted" : nil,
                        recurring > 0 ? "\(recurring) regression\(recurring == 1 ? "" : "s")" : nil,
                     ].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: f(12), design: .default))
                    .foregroundStyle(recurring > 0 ? Theme.rust : Theme.inkAlpha(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Ignore a finding and Dross won’t fail CI on it next scan.")
                    .font(.system(size: f(12), design: .default))
                    .foregroundStyle(Theme.inkAlpha(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var guideBlock: some View {
        VStack(alignment: .leading, spacing: f(8)) {
            SpecEyebrow(title: "Why here", extra: nil, scale: scale)
            Text("PR bots review diffs in the cloud. Dross is the pre-deploy pass for when you ship straight to main — especially contract drift between app and API.")
                .font(.system(size: f(12), design: .default))
                .foregroundStyle(Theme.inkAlpha(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shortcutsBlock: some View {
        VStack(alignment: .leading, spacing: f(10)) {
            SpecEyebrow(title: "Shortcuts", extra: nil, scale: scale)
            shortcutRow("⌘R", "Re-scan")
            shortcutRow("⌘↩", "Fix now")
            shortcutRow("Esc", "Close fix panel")
            shortcutRow("Click", "Edit finding in-app")
        }
    }

    private var actions: some View {
        VStack(spacing: f(8)) {
            SpecButton(title: "Re-scan", kind: .ghost, scale: scale, enabled: !scanning, action: onRescan)
                .keyboardShortcut("r", modifiers: .command)
            SpecButton(
                title: "Fix now",
                kind: .solid,
                scale: scale,
                enabled: report?.openFindings.isEmpty == false && !scanning,
                action: onFixNow
            )
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.bottom, f(28))
    }

    private func shortcutRow(_ key: String, _ label: String) -> some View {
        HStack(spacing: f(10)) {
            Text(key)
                .font(.system(size: f(11), weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .frame(width: f(44), alignment: .leading)
            Text(label)
                .font(.system(size: f(12), design: .default))
                .foregroundStyle(Theme.inkAlpha(0.5))
        }
    }

    private func displayName(_ check: String) -> String {
        check.replacingOccurrences(of: "-", with: " ")
    }
}
