import XCTest

final class TypeFilterTests: XCTestCase {
    func testFinderPNGIsDisplayedOnlyInImageFilter() throws {
        let entry = try makeFilesEntry(["/tmp/screenshot.png"])

        XCTAssertEqual(entry.type, .files, "storage type must keep file paste semantics")
        XCTAssertTrue(TypeFilter.image.matches(entry))
        XCTAssertFalse(TypeFilter.file.matches(entry))
    }

    func testMultipleImageFilesPreserveImageDisplayClassification() throws {
        let entry = try makeFilesEntry([
            "/tmp/first.jpg",
            "/tmp/second.heic",
            "/tmp/third.tiff"
        ])

        XCTAssertTrue(TypeFilter.image.matches(entry))
        XCTAssertFalse(TypeFilter.file.matches(entry))
    }

    func testMixedFilesRemainInFileFilter() throws {
        let entry = try makeFilesEntry([
            "/tmp/screenshot.png",
            "/tmp/document.pdf"
        ])

        XCTAssertFalse(TypeFilter.image.matches(entry))
        XCTAssertTrue(TypeFilter.file.matches(entry))
    }

    func testDocumentAndMalformedPayloadRemainFileEntries() throws {
        let document = try makeFilesEntry(["/tmp/document.pages"])
        let malformed = ClipboardEntry(
            type: .files,
            preview: "invalid",
            payload: #"{"path":"/tmp/screenshot.png"}"#
        )

        XCTAssertFalse(TypeFilter.image.matches(document))
        XCTAssertTrue(TypeFilter.file.matches(document))
        XCTAssertFalse(TypeFilter.image.matches(malformed))
        XCTAssertTrue(TypeFilter.file.matches(malformed))
    }

    func testCapturedImageStillMatchesImageFilter() {
        let entry = ClipboardEntry(
            type: .image,
            preview: "Image",
            payload: "/tmp/stored-image.png"
        )

        XCTAssertTrue(TypeFilter.image.matches(entry))
        XCTAssertFalse(TypeFilter.file.matches(entry))
    }

    private func makeFilesEntry(_ paths: [String]) throws -> ClipboardEntry {
        let data = try JSONEncoder().encode(paths)
        return ClipboardEntry(
            type: .files,
            preview: paths.first ?? "",
            payload: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
    }
}
