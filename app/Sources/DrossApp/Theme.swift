import SwiftUI

/// Ficha técnica — same language as TRACE / Aithority lab (`Sistema-UI/01-fundamentos`).
/// Bone page, ink type, one rust accent for things that need action.
/// Hairlines, sharp corners, no shadows. Folders on home are the only radius.
enum Theme {
    static let bone = Color(red: 0xF0 / 255, green: 0xF0 / 255, blue: 0xF0 / 255)
    static let ink = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    /// Findings / blocking — alerta, not decoration.
    static let rust = Color(red: 0xB8 / 255, green: 0x43 / 255, blue: 0x3F / 255)
    static let ok = Color(red: 0x3F / 255, green: 0x7A / 255, blue: 0x4E / 255)
    static let amberWarn = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255).opacity(0.55)

    static func inkAlpha(_ a: Double) -> Color { ink.opacity(a) }

    static let line = ink.opacity(0.22)
    static let hair = ink.opacity(0.14)

    static let mono = Font.system(.body, design: .monospaced)

    static func monoLabel(_ size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    static func sectionLabel(_ size: CGFloat = 9.5) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

/// Diagonal grain on the page. Panels sit on solid bone so the hatch
/// doesn’t show through (Sistema-UI trap #1).
struct PageGrain: View {
    var body: some View {
        Theme.bone
            .overlay(
                Canvas { ctx, size in
                    let step: CGFloat = 7
                    var path = Path()
                    var x: CGFloat = -size.height
                    while x < size.width + size.height {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                        x += step
                    }
                    ctx.stroke(path, with: .color(Theme.ink.opacity(0.035)), lineWidth: 1)
                }
                .allowsHitTesting(false)
            )
    }
}

struct SpecEyebrow: View {
    let title: String
    var extra: String? = nil
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(Theme.sectionLabel(9.5 * scale))
                .tracking(1.6)
                .foregroundStyle(Theme.inkAlpha(0.5))
            Spacer(minLength: 8)
            if let extra {
                Text(extra.uppercased())
                    .font(Theme.sectionLabel(9.5 * scale))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkAlpha(0.4))
            }
        }
    }
}

/// Progress as countable ticks — not a solid bar (HatchBar from the lab).
struct HatchBar: View {
    var filled: Int
    var total: Int
    var color: Color = Theme.rust
    var height: CGFloat = 10

    var body: some View {
        let ticks = max(total, 1)
        let on = min(max(filled, 0), ticks)
        HStack(spacing: 2) {
            ForEach(0..<ticks, id: \.self) { i in
                Rectangle()
                    .fill(i < on ? color : Theme.inkAlpha(0.13))
                    .frame(height: height)
            }
        }
    }
}

/// Label …… value — the most reused ficha-técnica row.
struct DottedRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.ink
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
            Text(label.uppercased())
                .font(Theme.sectionLabel(9.5 * scale))
                .tracking(1.1)
                .foregroundStyle(Theme.inkAlpha(0.45))
            Rectangle()
                .fill(Theme.inkAlpha(0.18))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            Text(value)
                .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
    }
}

enum SpecButtonKind { case solid, ghost }

struct SpecButton: View {
    let title: String
    var kind: SpecButtonKind = .solid
    var scale: CGFloat = 1
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(kind == .solid ? Theme.bone : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10 * scale)
                .background(kind == .solid ? Theme.ink : Color.clear)
                .overlay(
                    Rectangle().stroke(Theme.ink.opacity(kind == .ghost ? 0.3 : 0), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Top edge from the Swiss/brutalist refs — a 1-bit ruler, not a hairline.
struct CheckerStrip: View {
    var cell: CGFloat = 7
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            var i = 0
            while x < size.width {
                if i % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: cell, height: cell)), with: .color(Theme.ink))
                }
                x += cell
                i += 1
            }
        }
        .frame(height: cell)
        .background(Theme.bone)
    }
}

struct InkBadge: View {
    let text: String
    var alert: Bool = false
    var scale: CGFloat = 1
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5 * scale, weight: .medium, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Theme.bone)
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 6 * scale)
            .background(alert ? Theme.rust : Theme.ink)
    }
}

/// Rotated rail label — ARC “PRODUCT OVERVIEW” / “LIMITATIONS: …”
struct SpineLabel: View {
    let text: String
    var scale: CGFloat = 1
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
            .tracking(2.8)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .fixedSize()
            .rotationEffect(.degrees(-90), anchor: .center)
            .frame(width: 32 * scale)
            .frame(maxHeight: .infinity)
            .clipped()
    }
}
