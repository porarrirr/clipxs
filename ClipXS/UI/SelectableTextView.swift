import AppKit
import SwiftUI

/// Read-only text storage for previews. `NSTextView` can lay out only the
/// visible viewport, unlike a SwiftUI `Text` inside `ScrollView`, which eagerly
/// measures every line before the panel can appear.
final class SelectableTextScrollView: NSScrollView {
    let textView: NSTextView

    init(
        text: String,
        fontSize: CGFloat = 13,
        textContainerInset: NSSize = NSSize(width: 12, height: 12)
    ) {
        textView = NSTextView(frame: .zero)
        super.init(frame: .zero)

        borderType = .noBorder
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.layoutManager?.allowsNonContiguousLayout = true

        documentView = textView
        update(
            text: text,
            fontSize: fontSize,
            textContainerInset: textContainerInset
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        text: String,
        fontSize: CGFloat,
        textContainerInset: NSSize
    ) {
        textView.font = .systemFont(ofSize: fontSize)
        textView.textContainerInset = textContainerInset

        guard textView.string != text else { return }
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
    }
}

struct SelectableTextView: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 13
    var textContainerInset: NSSize = NSSize(width: 12, height: 12)

    func makeNSView(context: Context) -> SelectableTextScrollView {
        SelectableTextScrollView(
            text: text,
            fontSize: fontSize,
            textContainerInset: textContainerInset
        )
    }

    func updateNSView(_ scrollView: SelectableTextScrollView, context: Context) {
        scrollView.update(
            text: text,
            fontSize: fontSize,
            textContainerInset: textContainerInset
        )
    }
}
