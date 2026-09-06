import SwiftUI
import AppKit

/// A plain NSTextView + NSRulerView line-number gutter, wrapped for SwiftUI.
///
/// The previous approach put a separate SwiftUI VStack of line-number Text
/// views next to a TextEditor, trying to fake alignment by matching font
/// size and line spacing. That can never actually scroll in sync — the
/// gutter and the editor were two unrelated views, and TextEditor exposes
/// no API to reach its internal NSScrollView to keep them in step. This
/// wraps the real AppKit scroll view instead: the ruler is attached
/// directly to the same NSScrollView the text view scrolls in, so it moves
/// with the text as a side effect of how NSScrollView positions rulers,
/// not something this code has to hand-synchronize.
struct LineNumberTextEditor: NSViewRepresentable {
    @Binding var text: String
    var startLine: Int
    var fontSize: CGFloat = 11.5
    var textColor: NSColor = .labelColor
    var gutterColor: NSColor = .secondaryLabelColor

    func makeNSView(context: Context) -> NSScrollView {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = font
        textView.textColor = textColor
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.string = text
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        let ruler = LineNumberRulerView(textView: textView, startLine: startLine, font: font, textColor: gutterColor)
        scrollView.verticalRulerView = ruler

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
        context.coordinator.ruler?.startLine = startLine
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

/// Draws one right-aligned number per line of the attached text view's
/// content, at that line's actual on-screen Y position — not a guess at
/// line height, the real bounding rect AppKit's own layout manager computed
/// for that line, so it can't drift out of sync the way a hand-tuned
/// line-spacing constant could.
final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    var startLine: Int
    var font: NSFont
    var textColor: NSColor

    init(textView: NSTextView, startLine: Int, font: NSFont, textColor: NSColor) {
        self.textView = textView
        self.startLine = startLine
        self.font = font
        self.textColor = textColor
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 32
        NotificationCenter.default.addObserver(
            self, selector: #selector(contentDidChange),
            name: NSText.didChangeNotification, object: textView
        )
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not used") }

    @objc private func contentDidChange() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return }

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let inset = textView.textContainerInset
        let nsText = textView.string as NSString
        let length = nsText.length

        // A trailing "\n" produces one more, empty final line — same
        // line-count convention `draft.components(separatedBy: "\n")` uses
        // elsewhere (Save computes rangeEnd from that count), so numbering
        // here has to match it exactly or the two would disagree about
        // which line a save landed on.
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

            let y = rect.minY + inset.height
            let label = "\(lineNumber)"
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: y), withAttributes: attrs)
            lineNumber += 1

            if !hasContent { break }  // just drew the trailing phantom line (or text is empty) — done
            index = NSMaxRange(lineRange)
            guard index < length else {
                // Reached the end via real content. Only loop once more,
                // for the phantom trailing line, if the text actually ends
                // with a newline — otherwise this was the last line.
                if length > 0 && nsText.character(at: length - 1) == 10 { continue }
                break
            }
        }
    }
}
