import SwiftUI
import AppKit

/// A plain NSTextView wrapped for SwiftUI, with a line-number gutter drawn
/// by an `NSRulerView` attached to the scroll view.
///
/// History of what did *not* work, so it isn't retried:
///   1. A SwiftUI VStack of Text views next to TextEditor — no connection
///      to TextEditor's scroll position; it just sat still.
///   2. An NSRulerView whose only redraw trigger was text edits — it never
///      redrew on scroll, so it didn't move.
///   3. Drawing the numbers inside the NSTextView's own `draw(_:)` — on a
///      TextKit-2 / layer-backed text view the glyph layer composites over
///      anything the view draws itself, so the gutter was painted and then
///      hidden every frame (empty margin, no numbers).
///
/// This version goes back to NSRulerView — the purpose-built tool — but
/// fixes (2): the ruler is invalidated on *every* content-bounds change
/// (i.e. on scroll) as well as on text edits, so it tracks the text.
struct LineNumberTextEditor: NSViewRepresentable {
    @Binding var text: String
    var startLine: Int
    var fontSize: CGFloat = 11.5
    var textColor: NSColor = .labelColor
    var gutterColor: NSColor = .secondaryLabelColor
    var backgroundColor: NSColor = .textBackgroundColor
    var gutterWidth: CGFloat = 38

    func makeNSView(context: Context) -> NSScrollView {
        // Explicit TextKit 1 stack — a bare `NSTextView()` on macOS 12+ comes
        // up on TextKit 2, whose layout objects the ruler can't enumerate the
        // same way.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
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
        textView.textContainerInset = NSSize(width: 4, height: 6)
        // Standard resizable-in-a-scroll-view config: the text view must be
        // allowed to grow vertically past the visible clip height, or long
        // slices are clipped with no way to scroll to the rest.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        container.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NonGreedyScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor

        let ruler = LineNumberRulerView(textView: textView)
        ruler.startLine = startLine
        ruler.ruleThickness = gutterWidth
        ruler.gutterColor = gutterColor
        ruler.gutterBackground = backgroundColor.blended(withFraction: 0.05, of: .black) ?? backgroundColor
        ruler.gutterFont = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // (2) redraw the ruler on scroll, not only on edits.
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clip,
            queue: .main
        ) { [weak ruler] _ in ruler?.needsDisplay = true }
        NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak ruler] _ in ruler?.needsDisplay = true }

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
        }
        if context.coordinator.ruler?.startLine != startLine {
            context.coordinator.ruler?.startLine = startLine
        }
        context.coordinator.ruler?.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LineNumberTextEditor
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?

        init(_ parent: LineNumberTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            ruler?.needsDisplay = true
        }
    }
}

/// A scroll view that never reports an intrinsic size. Inside a SwiftUI
/// fixed-height panel, a plain NSScrollView demands its document view's full
/// height, so a code slice taller than the panel spills past the footer and
/// over the surrounding UI instead of scrolling within its own box.
final class NonGreedyScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// Draws the line numbers. Numbering follows the same
/// `components(separatedBy: "\n")` convention used elsewhere (Save computes
/// its range from that count): line N is the Nth `\n`-delimited slice, and a
/// trailing newline yields one more (empty) line.
final class LineNumberRulerView: NSRulerView {
    var startLine: Int = 1
    var gutterColor: NSColor = .secondaryLabelColor
    var gutterBackground: NSColor = .textBackgroundColor
    var gutterFont: NSFont = .monospacedSystemFont(ofSize: 11.5, weight: .regular)

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard
            let textView = clientView as? NSTextView,
            let layoutManager = textView.layoutManager,
            let container = textView.textContainer
        else { return }

        // Clip everything this method draws to the ruler's own bounds — a
        // partially-scrolled row would otherwise paint its number a few
        // pixels above the top edge, over the "Lines N–N" label that sits
        // just above the scroll view.
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: bounds).setClip()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }

        gutterBackground.setFill()
        bounds.fill()

        let attrs: [NSAttributedString.Key: Any] = [.font: gutterFont, .foregroundColor: gutterColor]
        let content = textView.string as NSString
        let visibleRect = textView.visibleRect
        let inset = textView.textContainerInset
        let fullRange = NSRange(location: 0, length: content.length)

        func drawNumber(_ n: Int, at y: CGFloat) {
            // Only rows whose baseline sits within the gutter get a number;
            // the clip above still trims a row straddling an edge.
            guard y > -gutterFont.pointSize, y < bounds.height else { return }
            let label = "\(n)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: y), withAttributes: attrs)
        }

        // Walk every logical (`\n`-delimited) line from the top of the
        // slice. The whole slice is small — this is simpler and less
        // error-prone than trying to seed the count from the first visible
        // character, which is what the earlier version got wrong.
        var lineIndex = 0
        content.enumerateSubstrings(
            in: fullRange, options: [.byLines, .substringNotRequired]
        ) { _, lineRange, _, _ in
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let frag = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location, effectiveRange: nil, withoutAdditionalLayout: true
            )
            drawNumber(self.startLine + lineIndex, at: frag.minY + inset.height - visibleRect.minY)
            lineIndex += 1
        }

        // A trailing '\n' leaves one more (empty) line that enumerateSubstrings
        // doesn't emit — matches `components(separatedBy: "\n")`.
        if content.length > 0, content.character(at: content.length - 1) == 10 {
            let extra = layoutManager.extraLineFragmentRect
            drawNumber(startLine + lineIndex, at: extra.minY + inset.height - visibleRect.minY)
        }
    }
}
