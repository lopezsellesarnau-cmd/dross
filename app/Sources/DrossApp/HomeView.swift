import SwiftUI

/// The multi-repo home screen from the Figma mock (DrossApp1).
///
/// Figma's frame is 1728pt wide; this window defaults to ~980pt. Using the
/// mock's raw point values verbatim (an earlier pass) rendered everything
/// oversized, because the SAME point size reads much bigger in a canvas
/// that's little more than half as wide. `scale` corrects for that — it's
/// the actual ratio between this window's width and the Figma frame's,
/// applied to every font size, padding, and the drawer illustration, so
/// proportions match instead of just raw numbers matching.
struct HomeView: View {
    @ObservedObject var store: RepoStore
    var displayName: String = "there"
    var onOpenRepo: (String) -> Void

    @State private var query = ""
    @State private var engineReady = true

    private let homeBackground = Theme.bone
    private let figmaDesignWidth: CGFloat = 1728

    private var filteredRepos: [TrackedRepo] {
        guard !query.isEmpty else { return store.repos }
        return store.repos.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, max(0.45, geo.size.width / figmaDesignWidth))
            content(scale: scale)
        }
        .background(PageGrain())
        .frame(minWidth: 980, minHeight: 700)
        .onAppear {
            engineReady = FileManager.default.fileExists(atPath: Engine.enginePath)
        }
    }

    private func content(scale: CGFloat) -> some View {
        func f(_ base: CGFloat) -> CGFloat { base * scale }

        return VStack(alignment: .leading, spacing: 0) {
            CheckerStrip(cell: f(7))
            datasheetMeta(f: f, scale: scale)
            Rectangle().fill(Theme.ink).frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                SpineLabel(text: "Repository index", scale: scale)
                    .frame(width: f(36))
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.ink).frame(width: 1) }

                PreviewsSidebar(
                    store: store,
                    repos: filteredRepos,
                    scale: scale,
                    onSelectRepo: { onOpenRepo($0.path) }
                )
                .frame(width: f(240))
                .padding(.horizontal, f(12))

                Rectangle().fill(Theme.ink).frame(width: 1)

                VStack(alignment: .leading, spacing: 0) {
                    homeHero(f: f)
                        .padding(.bottom, f(18))
                    if !engineReady {
                        Text("ENGINE MISSING — RUN `CD APP && ./REBUILD.SH`")
                            .font(.system(size: f(11), design: .monospaced))
                            .foregroundStyle(Theme.rust)
                            .padding(.bottom, f(12))
                    }
                    searchField(f: f)
                        .padding(.bottom, f(16))
                    ScrollView {
                        RepoStackListView(
                            repos: filteredRepos,
                            onSelect: { onOpenRepo($0.path) },
                            onAddRepo: pickFolder,
                            scale: scale,
                            backgroundColor: homeBackground
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .hideScrollChrome()
                }
                .padding(.leading, f(22))
                .padding(.trailing, f(16))
                .padding(.top, f(18))
                .padding(.bottom, f(22))

                Rectangle().fill(Theme.ink).frame(width: 1)

                HomeAssistRail(scale: scale, onAddRepo: pickFolder)
                    .frame(width: f(220))
                    .padding(.leading, f(14))
                    .padding(.top, f(18))

                SpineLabel(text: "Limitations: none registered", scale: scale)
                    .frame(width: f(28))
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.ink).frame(width: 1) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func datasheetMeta(f: (CGFloat) -> CGFloat, scale: CGFloat) -> some View {
        HStack(spacing: f(16)) {
            Text("TYPE: HOME / REPOS")
                .font(.system(size: f(10), weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
            Text("·")
                .foregroundStyle(Theme.inkAlpha(0.35))
            Text("DROSS")
                .font(.system(size: f(10), weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: f(8))
            Text("\(store.repos.count) INDEXED")
                .font(.system(size: f(10), weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
            InkBadge(text: "Local", scale: scale)
            Button(action: pickFolder) {
                Text("OPEN")
                    .font(.system(size: f(10), weight: .medium, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, f(16))
        .padding(.vertical, f(12))
    }

    private func homeHero(f: (CGFloat) -> CGFloat) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: f(10)) {
                Text("Welcome back, \(displayName).")
                    .font(.system(size: f(32), weight: .bold, design: .default))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.ink)
                Text("SCAN / FIX / VERIFY / COMMIT")
                    .font(.system(size: f(11), weight: .medium, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(Theme.inkAlpha(0.55))
                Text(">>>>>>>>>>>>>>>>")
                    .font(.system(size: f(11), weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: f(12))
            VStack(alignment: .trailing, spacing: f(6)) {
                HalftoneMark()
                    .frame(width: f(44), height: f(50))
                Text("STATUS: INDEX")
                    .font(.system(size: f(10), weight: .medium, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    // MARK: Search

    private func searchField(f: @escaping (CGFloat) -> CGFloat) -> some View {
        ZStack(alignment: .leading) {
            if query.isEmpty {
                Text("SEARCH REPOS")
                    .font(.system(size: f(11), weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkAlpha(0.35))
                    .padding(.horizontal, f(14))
            }
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: f(13), weight: .medium, design: .monospaced))
                .padding(.horizontal, f(14))
        }
        .frame(height: f(36))
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
        .background(Theme.bone)
    }

    private func pickFolder() {
        RepoPicker.present(onPicked: onOpenRepo)
    }
}
