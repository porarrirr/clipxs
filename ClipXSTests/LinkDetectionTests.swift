import XCTest

final class LinkDetectionTests: XCTestCase {
    private func entry(_ payload: String, type: ClipboardItemType = .text) -> ClipboardEntry {
        ClipboardEntry(type: type, preview: payload, payload: payload)
    }

    func testHttpAndHttpsUrlsAreLinks() {
        XCTAssertTrue(entry("https://example.com").isLink)
        XCTAssertTrue(entry("http://example.com/path?q=1").isLink)
        XCTAssertTrue(entry("  https://example.com  ").isLink, "surrounding whitespace is trimmed")
    }

    func testNonHttpSchemesAreNotLinks() {
        XCTAssertFalse(entry("ftp://example.com").isLink)
        XCTAssertFalse(entry("mailto:someone@example.com").isLink)
        XCTAssertFalse(entry("file:///tmp/x").isLink)
    }

    func testPlainTextIsNotLink() {
        XCTAssertFalse(entry("hello world").isLink)
        XCTAssertFalse(entry("visit https://example.com today").isLink, "embedded URL inside text is not a link entry")
        XCTAssertFalse(entry("").isLink)
    }

    func testNonTextTypesAreNeverLinks() {
        XCTAssertFalse(entry("https://example.com", type: .image).isLink)
        XCTAssertFalse(entry("https://example.com", type: .files).isLink)
    }

    func testOverlongTextIsNotLink() {
        let long = "https://example.com/" + String(repeating: "a", count: 3000)
        XCTAssertFalse(entry(long).isLink)
    }
}
