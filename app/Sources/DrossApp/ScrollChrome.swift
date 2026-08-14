import SwiftUI
import AppKit

/// macOS still paints legacy scroller tracks when System Settings →
/// "Show scroll bars" is Always — SwiftUI `.scrollIndicators(.hidden)`
/// alone is not enough. This walks up to the enclosing `NSScrollView`
/// and kills both scrollers.
struct KillScrollChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.strip(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.strip(from: nsView) }
    }

    private static func strip(from view: NSView) {
        var current: NSView? = view
        while let c = current {
            if let scroll = c as? NSScrollView {
                scroll.hasVerticalScroller = false
                scroll.hasHorizontalScroller = false
                scroll.autohidesScrollers = true
                scroll.scrollerStyle = .overlay
                scroll.verticalScroller?.isHidden = true
                scroll.horizontalScroller?.isHidden = true
                scroll.verticalScroller?.alphaValue = 0
                scroll.horizontalScroller?.alphaValue = 0
            }
            current = c.superview
        }
    }
}

extension View {
    /// Hide SwiftUI indicators + AppKit scroller chrome.
    func hideScrollChrome() -> some View {
        self
            .scrollIndicators(.hidden)
            .background(KillScrollChrome())
    }
}
