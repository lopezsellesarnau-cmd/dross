import SwiftUI

/// Welcome cover sheet — same datasheet chrome as Home / repo detail.
/// Left: pitch + CTAs. Right: opaque folder genealogy + a SPEC code sample.
struct WelcomeView: View {
    var onAuthenticated: (String) -> Void

    @State private var authMode: AuthPopup.Mode?
    @State private var brandIn = false
    @State private var sceneIn = false
    @State private var ctaFrame: CGRect = .zero

    private let pageBackground = Theme.bone

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, max(0.5, geo.size.width / 1728))
            VStack(spacing: 0) {
                CheckerStrip(cell: 7 * scale)
                metaBar(scale: scale)
                Rectangle().fill(Theme.ink).frame(height: 1)

                HStack(alignment: .top, spacing: 0) {
                    SpineLabel(text: "Pre-deploy scan", scale: scale)
                        .frame(width: 36 * scale)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .trailing) { Rectangle().fill(Theme.ink).frame(width: 1) }

                    brandAndCTA(scale: scale)
                        .frame(width: min(420, geo.size.width * 0.38), alignment: .topLeading)
                        .padding(.leading, 28 * scale)
                        .padding(.trailing, 20 * scale)
                        .padding(.top, 28 * scale)
                        .opacity(brandIn ? 1 : 0)
                        .offset(y: brandIn ? 0 : 10)

                    Rectangle().fill(Theme.ink).frame(width: 1)

                    WelcomeSpecimen(scale: scale, fill: pageBackground)
                        .padding(20 * scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .opacity(sceneIn ? 1 : 0)

                    SpineLabel(text: "Nothing leaves this Mac", scale: scale)
                        .frame(width: 28 * scale)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.ink).frame(width: 1) }
                }
                .frame(maxHeight: .infinity)
            }
            .background(PageGrain())
            .coordinateSpace(name: "welcome")
            .onPreferenceChange(CTAFrameKey.self) { ctaFrame = $0 }
            .overlay {
                if let authMode {
                    let panel = CGSize(
                        width: min(360, geo.size.width * 0.42),
                        height: authMode == .createAccount ? 400 : 348
                    )
                    let center = popupCenter(panel: panel, in: geo.size)
                    AuthPopup(
                        mode: authMode,
                        onClose: closeAuth,
                        onSuccess: { name in
                            closeAuth()
                            onAuthenticated(name)
                        },
                        onSwitchMode: { next in
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                                self.authMode = next
                            }
                        }
                    )
                    .frame(width: panel.width, height: panel.height)
                    .position(center)
                    .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.84), value: authMode != nil)
            .onAppear(perform: runEntrance)
        }
        .frame(minWidth: 880, minHeight: 560)
    }

    /// Sit the panel on the CTA cluster — just under the buttons, clamped to the window.
    private func popupCenter(panel: CGSize, in size: CGSize) -> CGPoint {
        let margin: CGFloat = 20
        let anchor = ctaFrame == .zero
            ? CGPoint(x: size.width * 0.28, y: size.height * 0.48)
            : CGPoint(x: ctaFrame.midX, y: ctaFrame.maxY + 10 + panel.height / 2)
        let x = min(max(anchor.x, margin + panel.width / 2), size.width - margin - panel.width / 2)
        let y = min(max(anchor.y, margin + panel.height / 2), size.height - margin - panel.height / 2)
        return CGPoint(x: x, y: y)
    }

    private func metaBar(scale: CGFloat) -> some View {
        HStack(spacing: 16 * scale) {
            Text("TYPE: APP / PRE-DEPLOY")
                .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
            Text("·")
                .foregroundStyle(Theme.inkAlpha(0.35))
            Text("DROSS")
                .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
            Spacer()
            InkBadge(text: "Field tested", scale: scale)
            Button(action: openSignIn) {
                Text("SIGN IN")
                    .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 12 * scale)
    }

    private func brandAndCTA(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HalftoneMark()
                .frame(width: 56 * scale, height: 64 * scale)
                .padding(.bottom, 16 * scale)

            Text("Scan before you ship.")
                .font(.system(size: 36 * scale, weight: .bold, design: .default))
                .tracking(-0.8)
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 12 * scale)

            Text("SCAN / FIX / VERIFY / COMMIT")
                .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(Theme.inkAlpha(0.55))
            Text(">>>>>>>>>>>>>>>>")
                .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 12 * scale)

            Text("Catch dead exports, demo stamps, env gaps, and contract drift before they hit main.")
                .font(.system(size: 11 * scale, design: .monospaced))
                .foregroundStyle(Theme.inkAlpha(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22 * scale)

            HStack(spacing: 10 * scale) {
                Button(action: openCreate) {
                    Text("CREATE ACCOUNT")
                        .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(pageBackground)
                        .padding(.horizontal, 16 * scale)
                        .padding(.vertical, 10 * scale)
                        .background(Theme.ink)
                }
                .buttonStyle(.plain)

                Button(action: openSignIn) {
                    Text("SIGN IN")
                        .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16 * scale)
                        .padding(.vertical, 10 * scale)
                        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CTAFrameKey.self,
                        value: proxy.frame(in: .named("welcome"))
                    )
                }
            )

            if authMode == nil {
                Text("SERIAL: LOCAL  ·  STATUS: STANDBY")
                    .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 16 * scale)
            }

            Spacer(minLength: 0)
        }
    }

    private func runEntrance() {
        withAnimation(.easeOut(duration: 0.45)) { brandIn = true }
        withAnimation(.easeOut(duration: 0.55).delay(0.12)) { sceneIn = true }
    }

    private func openCreate() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            authMode = .createAccount
        }
    }

    private func openSignIn() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            authMode = .signIn
        }
    }

    private func closeAuth() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            authMode = nil
        }
    }
}

// MARK: - Specimen (folders + spec code)

private struct WelcomeSpecimen: View {
    let scale: CGFloat
    let fill: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 22 * scale) {
            Text("SPECIMEN")
                .font(.system(size: 9.5 * scale, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Theme.inkAlpha(0.45))

            WelcomeExploded(scale: scale, fill: fill)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 268 * scale)

            WelcomeCodeSpec(scale: scale)
        }
    }
}

private struct WelcomeExploded: View {
    let scale: CGFloat
    let fill: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                WelcomeExplodedRails()
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1, lineCap: .square, lineJoin: .miter))

                tile("01  repo", depth: 6, add: false, s: 0.84 * scale)
                    .offset(x: w * 0.00, y: h * 0.14)
                tile("02  app", depth: 3, add: false, s: 0.50 * scale)
                    .offset(x: w * 0.46, y: h * 0.00)
                tile("03  api", depth: 5, add: false, s: 0.48 * scale)
                    .offset(x: w * 0.56, y: h * 0.38)
                tile("+ open", depth: 1, add: true, s: 0.42 * scale)
                    .offset(x: w * 0.16, y: h * 0.62)

                callout("ROOT  ·  UNIT UNDER TEST", x: w * 0.00, y: h * 0.02)
                callout("CLIENT TREE", x: w * 0.46, y: max(0, h * 0.00))
                callout("API  ·  DRIFT", rust: true, x: w * 0.56, y: h * 0.38 - 16 * scale)
                callout("SCAN TARGET", x: w * 0.16, y: h * 0.62 - 16 * scale)
            }
        }
    }

    private func tile(_ label: String, depth: Int, add: Bool, s: CGFloat) -> some View {
        FolderStack(
            label: label,
            depth: depth,
            isAdd: add,
            scale: s,
            backgroundColor: fill
        )
    }

    private func callout(_ text: String, rust: Bool = false, x: CGFloat, y: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            Circle().fill(rust ? Theme.rust : Theme.ink).frame(width: 4 * scale, height: 4 * scale)
            Text(text)
                .font(.system(size: 9 * scale, weight: .medium, design: .monospaced))
                .tracking(1.3)
                .foregroundStyle(rust ? Theme.rust : Theme.ink)
        }
        .offset(x: x, y: y)
    }
}

/// Rails between the four units — relative to the exploded frame.
private struct WelcomeExplodedRails: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let repo = CGPoint(x: rect.width * 0.22, y: rect.height * 0.38)
        let app = CGPoint(x: rect.width * 0.48, y: rect.height * 0.16)
        let api = CGPoint(x: rect.width * 0.56, y: rect.height * 0.52)
        let open = CGPoint(x: rect.width * 0.28, y: rect.height * 0.72)

        func elbow(_ a: CGPoint, _ b: CGPoint) {
            let midX = (a.x + b.x) / 2
            p.move(to: a)
            p.addLine(to: CGPoint(x: midX, y: a.y))
            p.addLine(to: CGPoint(x: midX, y: b.y))
            p.addLine(to: b)
        }
        elbow(repo, app)
        elbow(repo, api)
        elbow(repo, open)

        for pt in [repo, app, api, open] {
            p.move(to: CGPoint(x: pt.x - 4, y: pt.y))
            p.addLine(to: CGPoint(x: pt.x + 4, y: pt.y))
            p.move(to: CGPoint(x: pt.x, y: pt.y - 4))
            p.addLine(to: CGPoint(x: pt.x, y: pt.y + 4))
        }
        return p
    }
}

private struct CTAFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct WelcomeCodeSpec: View {
    let scale: CGFloat

    private let lines: [(text: String, drift: Bool)] = [
        ("// app/client.ts", false),
        ("await fetch(\"/v1/users\", {", false),
        ("  method: \"GET\",", false),
        ("  headers: { Authorization: token }", false),
        ("})", false),
        ("", false),
        ("// api/server.ts", false),
        ("app.post(\"/v2/users\", auth, handler)", true),
        ("// method + path no longer match the client", true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CHECK")
                    .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Theme.bone)
                Spacer()
                Text("CONTRACT-DRIFT")
                    .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.bone.opacity(0.75))
            }
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 8 * scale)
            .background(Theme.ink)

            HStack {
                Text("FILE: client.ts")
                Spacer()
                Text("SIGNAL: HIGH")
                    .foregroundStyle(Theme.rust)
            }
            .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 8 * scale)
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3 * scale) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                        .foregroundStyle(line.drift ? Theme.rust : Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12 * scale)
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
        }
    }
}

#Preview {
    WelcomeView(onAuthenticated: { _ in })
        .frame(width: 1200, height: 780)
}
