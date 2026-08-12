import SwiftUI

/// The real logo — Desktop/ICON/icon final.png, bundled as a resource, not
/// a procedural approximation. `accentFraction` still gives a lightweight
/// "this scan has findings" signal (a faint red wash), since the exact
/// per-dot tinting the earlier generative version did isn't possible on a
/// flat raster image.
struct HalftoneMark: View {
    var accentFraction: Double = 0

    private static let image: NSImage? = {
        Bundle.module.url(forResource: "icon-final", withExtension: "png", subdirectory: "Resources")
            .flatMap { NSImage(contentsOf: $0) }
    }()

    var body: some View {
        Group {
            if let nsImage = Self.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .colorMultiply(accentFraction > 0.25 ? Theme.rust : .white)
            } else {
                // Bundle lookup failed — fail visibly (a blank ink square),
                // not silently with a placeholder that looks intentional.
                Rectangle().fill(Theme.inkAlpha(0.15))
            }
        }
    }
}

#Preview {
    HalftoneMark()
        .frame(width: 120, height: 120)
        .padding(30)
        .background(Theme.bone)
}
