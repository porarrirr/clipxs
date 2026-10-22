import AppKit
import XCTest

final class PasteboardRestoreTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var tempDir: URL!

    override func setUpWithError() throws {
        pasteboard = NSPasteboard(name: .init("com.clipxs.tests.\(UUID().uuidString)"))
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipXSTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFilesEntry(paths: [String]) -> ClipboardEntry {
        let data = try! JSONEncoder().encode(paths)
        let payload = String(data: data, encoding: .utf8)!
        return ClipboardEntry(type: .files, preview: "files", payload: payload)
    }

    func testFolderRestoreDoesNotExposePlainTextPath() throws {
        let folderURL = tempDir.appendingPathComponent("MyFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let entry = makeFilesEntry(paths: [folderURL.path])
        let ok = PasteboardRestore.restore(entry, to: pasteboard)

        XCTAssertTrue(ok)
        // A target that reads file objects still gets the real folder.
        let readURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(readURLs, [folderURL])
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testMultipleFilesRestoreKeepsAttachmentsWithoutPathText() throws {
        let fileA = tempDir.appendingPathComponent("a.txt")
        let fileB = tempDir.appendingPathComponent("b.txt")
        try "a".write(to: fileA, atomically: true, encoding: .utf8)
        try "b".write(to: fileB, atomically: true, encoding: .utf8)

        let entry = makeFilesEntry(paths: [fileA.path, fileB.path])
        XCTAssertTrue(PasteboardRestore.restore(entry, to: pasteboard))

        XCTAssertNil(pasteboard.string(forType: .string))
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls, [fileA, fileB])
    }

    private func makeImageFile(_ name: String) throws -> URL {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let url = tempDir.appendingPathComponent(name)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    func testMultipleImagesRestoreAsSeparateAttachmentsWithoutPathText() throws {
        let urls = try [makeImageFile("first.png"), makeImageFile("日本語 second.png")]
        let entry = makeFilesEntry(paths: urls.map(\.path))
        XCTAssertTrue(PasteboardRestore.restore(entry, to: pasteboard))
        XCTAssertNil(pasteboard.string(forType: .string))
        let items = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        for (item, url) in zip(items, urls) {
            XCTAssertEqual(item.string(forType: .fileURL), url.absoluteString)
            XCTAssertNotNil(item.data(forType: .png).flatMap(NSImage.init(data:)))
            XCTAssertNotNil(item.data(forType: .tiff).flatMap(NSImage.init(data:)))
        }
        let readURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(readURLs, urls)
    }

    func testRawImageAndImageFileMergeRestoreBothAttachments() throws {
        let first = try makeImageFile("captured.png")
        let second = try makeImageFile("finder.png")
        let merged = try XCTUnwrap(ClipboardEntry.merging([
            ClipboardEntry(type: .image, preview: "image", payload: first.path),
            makeFilesEntry(paths: [second.path])
        ]))
        XCTAssertEqual(merged.fileURLs, [first, second])
        XCTAssertTrue(PasteboardRestore.restore(merged, to: pasteboard))
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testMissingAttachmentFailsInsteadOfSilentlyPastingSubset() throws {
        let existing = try makeImageFile("exists.png")
        let entry = makeFilesEntry(paths: [existing.path, tempDir.appendingPathComponent("missing.png").path])
        XCTAssertFalse(PasteboardRestore.restore(entry, to: pasteboard))
        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true)
    }

    func testMissingFilesAndImagesLeaveExistingClipboardUntouched() {
        for entry in [makeFilesEntry(paths: [tempDir.appendingPathComponent("missing.pdf").path]),
                      ClipboardEntry(type: .image, preview: "missing", payload: tempDir.appendingPathComponent("missing.png").path),
                      ClipboardEntry(type: .files, preview: "invalid", payload: "not JSON")] {
            pasteboard.clearContents()
            pasteboard.setString("existing 日本語", forType: .string)
            let count = pasteboard.changeCount
            XCTAssertFalse(PasteboardRestore.restore(entry, to: pasteboard))
            XCTAssertEqual(pasteboard.changeCount, count)
            XCTAssertEqual(pasteboard.string(forType: .string), "existing 日本語")
        }
    }

    func testWriteFailureRollsBackAllPreviousItemsAndRepresentations() {
        let first = NSPasteboardItem()
        first.setString("first", forType: .string)
        first.setData(Data("<b>first</b>".utf8), forType: .html)
        let second = NSPasteboardItem()
        second.setString("second", forType: .string)
        pasteboard.writeObjects([first, second])
        let replacement = NSPasteboardItem()
        replacement.setString("replacement", forType: .string)
        XCTAssertFalse(PasteboardRestore.replaceContents([replacement], on: pasteboard) { board, items in
            // Simulate a writer that mutates the clipboard before failing.
            _ = board.writeObjects(items)
            return false
        })
        XCTAssertEqual(pasteboard.pasteboardItems?.map { $0.string(forType: .string) }, ["first", "second"])
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.data(forType: .html), Data("<b>first</b>".utf8))
    }

    func testMissingFileFailsRestore() {
        let entry = makeFilesEntry(paths: [tempDir.appendingPathComponent("missing").path])
        XCTAssertFalse(PasteboardRestore.restore(entry, to: pasteboard))
    }
}

@MainActor
final class PasteboardCaptureTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var directory: URL!

    override func setUpWithError() throws {
        pasteboard = NSPasteboard(name: .init("com.clipxs.capture-tests.\(UUID().uuidString)"))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipXSCaptureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    func testHTMLOnlyCopyCapturesPlainTextAndPreservesFormatting() throws {
        let html = Data("<html><meta charset='utf-8'><body><b>日本語 &amp; hello</b><br>second</body></html>".utf8)
        pasteboard.setData(html, forType: .html)
        let captured = try XCTUnwrap(PasteboardCapture.capture(from: pasteboard))
        XCTAssertEqual(captured.entry.type, .text)
        XCTAssertTrue(captured.entry.payload.contains("日本語 & hello"))
        XCTAssertTrue(captured.entry.payload.contains("second"))
        XCTAssertEqual(captured.entry.richFormat, .html)
        XCTAssertEqual(captured.entry.richPayload, html)
        XCTAssertTrue(PasteboardRestore.restore(captured.entry, to: pasteboard))
        XCTAssertEqual(pasteboard.data(forType: .html), html)
        XCTAssertEqual(pasteboard.string(forType: .string), captured.entry.payload)
        XCTAssertTrue(PasteboardRestore.restore(captured.entry, plainTextOnly: true, to: pasteboard))
        XCTAssertNil(pasteboard.data(forType: .html))
        XCTAssertEqual(pasteboard.string(forType: .string), captured.entry.payload)
    }

    func testMixedCopyRoundTripsTextFilesRichTextAndOrder() throws {
        let first = NSPasteboardItem()
        first.setString("before 日本語", forType: .string)
        first.setData(Data("<b>before 日本語</b>".utf8), forType: .html)
        let fileURL = directory.appendingPathComponent("document.pdf")
        try Data("%PDF-1.4".utf8).write(to: fileURL)
        let file = NSPasteboardItem()
        file.setString(fileURL.absoluteString, forType: .fileURL)
        // A file's alternate path representation must not be counted as text.
        file.setString(fileURL.path, forType: .string)
        let last = NSPasteboardItem()
        last.setString("after", forType: .string)
        pasteboard.writeObjects([first, file, last])
        let captured = try XCTUnwrap(PasteboardCapture.capture(from: pasteboard, sourceBundleId: "com.test.source"))
        XCTAssertEqual(captured.entry.fileURLs, [fileURL])
        XCTAssertEqual(captured.entry.accompanyingText, "before 日本語\nafter")
        XCTAssertEqual(captured.entry.sourceBundleId, "com.test.source")
        XCTAssertEqual(captured.entry.preservedParts?.count, 3)
        XCTAssertFalse(captured.entry.isImageForDisplay)
        XCTAssertTrue(PasteboardRestore.restore(captured.entry, to: pasteboard))
        let restored = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(restored.count, 3)
        XCTAssertEqual(restored[0].string(forType: .string), "before 日本語")
        XCTAssertEqual(restored[0].data(forType: .html), Data("<b>before 日本語</b>".utf8))
        XCTAssertEqual(restored[1].string(forType: .fileURL), fileURL.absoluteString)
        XCTAssertNil(restored[1].string(forType: .string))
        XCTAssertEqual(restored[2].string(forType: .string), "after")
        let recaptured = try XCTUnwrap(PasteboardCapture.capture(from: pasteboard))
        XCTAssertEqual(recaptured.contentHash, captured.contentHash)
        XCTAssertEqual(recaptured.entry.preservedParts, captured.entry.preservedParts)
    }

    func testOrdinaryFileAlternatePathTextDoesNotBecomeMixedCopy() throws {
        let fileURL = directory.appendingPathComponent("archive.zip")
        try Data().write(to: fileURL)
        let file = NSPasteboardItem()
        file.setString(fileURL.absoluteString, forType: .fileURL)
        file.setString(fileURL.path, forType: .string)
        pasteboard.writeObjects([file])
        let captured = try XCTUnwrap(PasteboardCapture.capture(from: pasteboard))
        XCTAssertNil(captured.entry.preservedParts)
        XCTAssertEqual(captured.entry.fileURLs, [fileURL])
        XCTAssertTrue(PasteboardRestore.restore(captured.entry, to: pasteboard))
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testMixedEntryWithMissingFileDoesNotReplaceClipboard() throws {
        let paths = [directory.appendingPathComponent("gone.pdf").path]
        let data = try JSONEncoder().encode(FileClipboardPayload(paths: paths, parts: [
            .text(plain: "retain this", rich: nil, format: nil), .file(path: paths[0])
        ]))
        let entry = ClipboardEntry(type: .files, preview: "mixed", payload: String(data: data, encoding: .utf8)!)
        pasteboard.setString("original", forType: .string)
        XCTAssertFalse(PasteboardRestore.restore(entry, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }
}
