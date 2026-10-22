import XCTest

final class TextTransformTests: XCTestCase {
    func testUppercased() {
        XCTAssertEqual(TextTransform.uppercased.apply(to: "Hello World"), "HELLO WORLD")
    }

    func testLowercased() {
        XCTAssertEqual(TextTransform.lowercased.apply(to: "Hello World"), "hello world")
    }

    func testRemoveLineBreaks() {
        XCTAssertEqual(
            TextTransform.removeLineBreaks.apply(to: "line1\nline2\r\nline3"),
            "line1 line2 line3"
        )
    }

    func testRemoveLineBreaksKeepsOtherWhitespace() {
        XCTAssertEqual(
            TextTransform.removeLineBreaks.apply(to: "a  b\nc"),
            "a  b c"
        )
    }

    func testCollapseWhitespace() {
        XCTAssertEqual(
            TextTransform.collapseWhitespace.apply(to: "  a \t b\n\n c  "),
            "a b c"
        )
    }

    func testURLDecode() {
        XCTAssertEqual(
            TextTransform.urlDecoded.apply(to: "https://example.com/%E3%83%86%E3%82%B9%E3%83%88?q=a%20b"),
            "https://example.com/テスト?q=a b"
        )
    }

    func testURLDecodeInvalidSequenceReturnsInput() {
        XCTAssertEqual(TextTransform.urlDecoded.apply(to: "100%zz"), "100%zz")
    }
}
