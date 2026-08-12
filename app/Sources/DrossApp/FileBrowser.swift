import SwiftUI

/// A folder/file node, children loaded lazily on expand — not the whole disk
/// tree upfront, which would be slow and pointless for anything past a
/// couple of levels deep.
final class FileNode: Identifiable, ObservableObject {
    let id: String // absolute path — stable across reloads
    let name: String
    let path: String
    let isDirectory: Bool
    @Published var children: [FileNode]?

    init(path: String, isDirectory: Bool) {
        self.id = path
        self.path = path
        self.name = (path as NSString).lastPathComponent
        self.isDirectory = isDirectory
    }

    func loadChildrenIfNeeded() {
        guard isDirectory, children == nil else { return }
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        let hidden: Set<String> = ["node_modules", ".git", "dist", "build", ".next", ".expo", "coverage", "Pods"]
        children = entries
            .filter { !$0.hasPrefix(".") && !hidden.contains($0) }
            .sorted()
            .map { entry -> FileNode in
                let fullPath = (path as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                return FileNode(path: fullPath, isDirectory: isDir.boolValue)
            }
    }
}

/// Right-side sidebar — pick a repo (or a file inside it, for the code
/// preview) by browsing, the way Finder or the portfolio's folder UI works,
/// instead of typing a raw path into a text field.
struct FileBrowserView: View {
    @Binding var rootPath: String
    var onPickRepo: (String) -> Void
    var onPickFile: (String) -> Void

    @State private var root: FileNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FILES").font(Theme.monoLabel(10)).tracking(1).foregroundStyle(Theme.inkAlpha(0.6))
                Spacer()
                Button(action: pickFolder) {
                    Text("OPEN…").font(Theme.monoLabel(9.5)).foregroundStyle(Theme.inkAlpha(0.55))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider().overlay(Theme.inkAlpha(0.18))

            if let root {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        FileRow(node: root, depth: 0, onPickRepo: onPickRepo, onPickFile: onPickFile)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No folder open.").font(Theme.monoLabel(10.5)).foregroundStyle(Theme.inkAlpha(0.45))
                    Button(action: pickFolder) {
                        Text("CHOOSE A REPO").font(Theme.monoLabel(10)).foregroundStyle(Theme.rust)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
        }
        .frame(width: 240)
        .background(Theme.inkAlpha(0.03))
        .onChange(of: rootPath) { _, newValue in
            guard !newValue.isEmpty, FileManager.default.fileExists(atPath: newValue) else { return }
            let node = FileNode(path: newValue, isDirectory: true)
            node.loadChildrenIfNeeded()
            root = node
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
            onPickRepo(url.path)
        }
    }
}

private struct FileRow: View {
    @ObservedObject var node: FileNode
    let depth: Int
    var onPickRepo: (String) -> Void
    var onPickFile: (String) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    // A dot, not a folder/doc glyph — same "no generic icons,
                    // the dot is the vocabulary" rule as the rest of the app.
                    Circle()
                        .fill(node.isDirectory ? Theme.inkAlpha(0.55) : Theme.inkAlpha(0.3))
                        .frame(width: node.isDirectory ? 6 : 4, height: node.isDirectory ? 6 : 4)
                    Text(node.name)
                        .font(Theme.monoLabel(11))
                        .foregroundStyle(node.isDirectory ? Theme.ink : Theme.inkAlpha(0.75))
                    Spacer()
                }
                .padding(.leading, CGFloat(depth) * 14 + 14)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, let children = node.children {
                ForEach(children) { child in
                    FileRow(node: child, depth: depth + 1, onPickRepo: onPickRepo, onPickFile: onPickFile)
                }
            }
        }
    }

    private func toggle() {
        if node.isDirectory {
            node.loadChildrenIfNeeded()
            expanded.toggle()
            onPickRepo(node.path) // clicking any folder rescans from there — browsing IS picking
        } else {
            onPickFile(node.path)
        }
    }
}
