import XCTest

final class ClipboardEntryFileURLsTests: XCTestCase {
    func testSingleFilePayloadDecodesToFileURL() throws {
        let path = "/tmp/preview.png"
        let entry = ClipboardEntry(
            type: .files,
            preview: "preview.png",
            payload: try encodedPayload([path])
        )

        XCTAssertEqual(entry.fileURLs, [URL(fileURLWithPath: path)])
    }

    func testMultipleFilePayloadPreservesOriginalOrder() throws {
        let paths = [
            "/tmp/first.png",
            "/tmp/second.pdf",
            "/tmp/third.mov"
        ]
        let entry = ClipboardEntry(
            type: .files,
            preview: "3 files",
            payload: try encodedPayload(paths)
        )

        XCTAssertEqual(entry.fileURLs.map(\.path), paths)
    }

    func testInvalidFilePayloadReturnsNoURLs() {
        let malformedJSON = ClipboardEntry(
            type: .files,
            preview: "invalid",
            payload: #"{"path":"/tmp/file.png"}"#
        )
        let relativePath = ClipboardEntry(
            type: .files,
            preview: "relative",
            payload: #"["/tmp/file.png", "relative/file.png"]"#
        )
        let wrongType = ClipboardEntry(
            type: .text,
            preview: "text",
            payload: #"["/tmp/file.png"]"#
        )

        XCTAssertTrue(malformedJSON.fileURLs.isEmpty)
        XCTAssertTrue(relativePath.fileURLs.isEmpty)
        XCTAssertTrue(wrongType.fileURLs.isEmpty)
    }

    private func encodedPayload(_ paths: [String]) throws -> String {
        let data = try JSONEncoder().encode(paths)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
