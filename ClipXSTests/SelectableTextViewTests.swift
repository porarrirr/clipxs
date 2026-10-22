import AppKit
import XCTest

final class SelectableTextViewTests: XCTestCase {
    @MainActor
    func testLongPreviewKeepsFullTextAndUsesViewportLayout() {
        let longText = String(repeating: "x\n", count: 3_000)

        let scrollView = SelectableTextScrollView(text: longText)
        scrollView.frame = NSRect(x: 0, y: 0, width: 380, height: 380)
        scrollView.layoutSubtreeIfNeeded()

        XCTAssertEqual(scrollView.textView.string, longText)
        XCTAssertTrue(scrollView.textView.layoutManager?.allowsNonContiguousLayout == true)
        XCTAssertTrue(scrollView.textView.isSelectable)
        XCTAssertFalse(scrollView.textView.isEditable)
        XCTAssertFalse(scrollView.textView.isRichText)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertTrue(scrollView.textView.textContainer?.widthTracksTextView == true)
        XCTAssertEqual(scrollView.textView.frame.width, scrollView.contentSize.width)
    }

    @MainActor
    func testTextUpdateResetsSelectionAndScrollsToStart() {
        let scrollView = SelectableTextScrollView(text: "old text")
        scrollView.textView.setSelectedRange(NSRange(location: 4, length: 4))

        scrollView.update(
            text: "new text",
            fontSize: 13,
            textContainerInset: NSSize(width: 12, height: 12)
        )

        XCTAssertEqual(scrollView.textView.string, "new text")
        XCTAssertEqual(scrollView.textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    @MainActor
    func testUnchangedUpdatePreservesUserSelection() {
        let text = "selectable text"
        let scrollView = SelectableTextScrollView(text: text)
        let selection = NSRange(location: 0, length: 10)
        scrollView.textView.setSelectedRange(selection)

        scrollView.update(
            text: text,
            fontSize: 13,
            textContainerInset: NSSize(width: 12, height: 12)
        )

        XCTAssertEqual(scrollView.textView.selectedRange(), selection)
    }
}
