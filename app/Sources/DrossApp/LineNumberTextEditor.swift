import SwiftUI
import AppKit

/// A plain NSTextView wrapped for SwiftUI, with line numbers drawn directly
/// into its own left margin — not a second view trying to track this one.
///
/// Two earlier approaches both failed for the same underlying reason: a
/// gutter that lives in a *different* view than the text can only ever
/// approximate staying in sync with it.
///   1. A SwiftUI VStack of Text views next to TextEditor — no connection
///      to TextEditor's internal scroll position at all; it just sat still.
///   2. An NSRulerView attached to the same NSScrollView — closer, but
///      NSRulerView only redraws when told to, and the only redraw trigger
///      wired up was text *edits*, not scrolling, so it still didn't move;
///      it also paints its own default (opaque, wrong-colored) background.
/// This version draws the numbers in NumberedTextView's own `draw(_:)`,
/// right after the text itself — the same view, the same draw pass, the
/// same scroll offset, automatically. There's nothing to keep in sync
/// because there's only one view.
struct LineNumberTextEditor: NSViewRepresentable {
    @Binding var text: String
    var startLine: Int
    var fontSize: CGFloat = 11.5
    var textColor: NSColor = .labelColor
    var gutterColor: NSColor = .secondaryLabelColor
    var backgroundColor: NSColor = .textBackgroundColor
    var gutterWidth: CGFloat = 38

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NumberedTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = textColor
        textView.drawsBackground = true
        textView.backgroundColor = backgroundColor
        textView.delegate = context.coordinator
        textView.string = text
        // Reserve the gutter as left+right inset (NSTextView insets the
        // text container equally on both sides) — the right side loses the
        // same width to nothing, an acceptable trade for a popup this
        // narrow rather than fighting the text container's geometry to
        // make the inset asymmetric.
        textView.textContainerInset = NSSize(width: gutterWidth, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.gutterWidth = gutterWidth
        textView.gutterColor = gutterColor
        textView.gutterFont = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.startLine = startLine

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
        }
        if textView.startLine != startLine {
            textView.startLine = startLine
            textView.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LineNumberTextEditor
        weak var textView: NumberedTextView?

        init(_ parent: LineNumberTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

/// The text view itself draws its line numbers — see the type comment on
/// LineNumberTextEditor for why this replaced two separate-view attempts.
/// The numbers live entirely in `draw(_:)`; they're pixels, not text-view
/// content, so there's no glyph or character storage for them at all —
/// they can't be selected, edited, or deleted along with the code because
/// they were never part of the document in the first place.
final class NumberedTextView: NSTextView {
    var startLine: Int = 1
    var gutterWidth: CGFloat = 38
    var gutterColor: NSColor = .secondaryLabelColor
    var gutterFont: NSFont = .monospacedSystemFont(ofSize: 11.5, weight: .regular)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawGutterBackground()
        drawLineNumbers()
    }

    /// Paints over the reserved left margin so it reads as one distinct
    /// panel rather than numbers floating on the same surface as the code
    /// — same background as the rest, one shade darker, same shade for
    /// every line since it's a single fill, not drawn per-line.
    private func drawGutterBackground() {
        guard let scrollView = enclosingScrollView else { return }
        let visible = visibleRect
        let gutterRect = NSRect(x: visible.minX, y: visible.minY, width: gutterWidth, height: visible.height)
        (backgroundColor.blended(withFraction: 0.05, of: .black) ?? backgroundColor).setFill()
        gutterRect.fill()
        _ = scrollView
    }

    private func drawLineNumbers() {
        guard let layoutManager, let container = textContainer else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: gutterFont, .foregroundColor: gutterColor]
        let nsText = string as NSString
        let length = nsText.length

        // Same line-count convention `draft.components(separatedBy: "\n")`
        // uses elsewhere (Save computes rangeEnd from that count): a
        // trailing "\n" gets one more, empty final line numbered too.
        var lineNumber = startLine
        var index = 0
        while true {
            let lineRange = nsText.lineRange(for: NSRange(location: index, length: 0))
            let hasContent = lineRange.length > 0
            let rect: NSRect
            if hasContent {
                let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
                rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            } else {
                rect = layoutManager.extraLineFragmentRect
            }

            // Same left inset for every line — one fixed number, not
            // recomputed per line, so the gap between the gutter and the
            // code text is identical for every row.
            let y = rect.minY + textContainerInset.height
            let label = "\(lineNumber)"
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: gutterWidth - size.width - 8, y: y), withAttributes: attrs)
            lineNumber += 1

            if !hasContent { break }
            index = NSMaxRange(lineRange)
            guard index < length else {
                if length > 0 && nsText.character(at: length - 1) == 10 { continue }
                break
            }
        }
    }
}
