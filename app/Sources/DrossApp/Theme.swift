import SwiftUI

/// Same house system as Aithority (terracotta) and TRACE (amber) — bone
/// background, ink text, hairline borders, monospace uppercase labels.
/// Dross stays deliberately monochrome — red is the ONE exception,
/// reserved strictly for real findings (a "finding" severity), never used
/// decoratively. "warning" severity (an unnecessary-but-harmless export,
/// say) is a mid-ink gray, not a second accent color — there's exactly one
/// thing in this app worth an accent: something that needs fixing.
enum Theme {
    static let bone = Color(red: 0xF0 / 255, green: 0xEE / 255, blue: 0xE9 / 255)
    static let ink = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    static let rust = Color(red: 0xC1 / 255, green: 0x3D / 255, blue: 0x2A / 255)
    static let amberWarn = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255).opacity(0.55)

    static func inkAlpha(_ a: Double) -> Color { ink.opacity(a) }

    static let mono = Font.system(.body, design: .monospaced)

    static func monoLabel(_ size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}
