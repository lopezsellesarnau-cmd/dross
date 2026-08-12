import SwiftUI

/// The "action side" panel: not just a message string, the actual source
/// around the flagged line, so the user can see exactly what to remove or
/// fix without alt-tabbing to their editor.
struct CodePreviewView: View {
    let repoRoot: String
    let finding: Finding
    var onClose: () -> Void

    private var lines: [(number: Int, text: String)] {
        let fullPath = (repoRoot as NSString).appendingPathComponent(finding.file)
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { return [] }
        let allLines = content.components(separatedBy: "\n")
        let target = (finding.line ?? 1)
        let context = 4
        let start = max(1, target - context)
        let end = min(allLines.count, target + context)
        guard start <= end else { return [] }
        return (start...end).map { ($0, allLines[$0 - 1]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.file).font(Theme.monoLabel(11)).foregroundStyle(Theme.ink)
                    Text(finding.message).font(.system(size: 11)).foregroundStyle(Theme.inkAlpha(0.65)).lineLimit(2)
                }
                Spacer()
                Button(action: onClose) {
                    Text("CLOSE").font(Theme.monoLabel(9.5)).foregroundStyle(Theme.inkAlpha(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            Divider().overlay(Theme.inkAlpha(0.18))

            if lines.isEmpty {
                Text("Couldn't read this file from disk.")
                    .font(Theme.monoLabel(10.5))
                    .foregroundStyle(Theme.inkAlpha(0.5))
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines, id: \.number) { line in
                            let isTarget = line.number == finding.line
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(line.number)")
                                    .font(Theme.mono)
                                    .frame(width: 32, alignment: .trailing)
                                    .foregroundStyle(isTarget ? Theme.rust : Theme.inkAlpha(0.35))
                                Text(line.text.isEmpty ? " " : line.text)
                                    .font(Theme.mono)
                                    .foregroundStyle(isTarget ? Theme.ink : Theme.inkAlpha(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .background(isTarget ? Theme.rust.opacity(0.1) : Color.clear)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Theme.bone)
        .overlay(Rectangle().stroke(Theme.inkAlpha(0.18), lineWidth: 1))
    }
}
