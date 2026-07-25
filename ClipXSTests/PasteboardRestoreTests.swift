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

    func testFolderRestoreAlsoExposesPlainTextPath() throws {
        let folderURL = tempDir.appendingPathComponent("MyFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let entry = makeFilesEntry(paths: [folderURL.path])
        let ok = PasteboardRestore.restore(entry, to: pasteboard)

        XCTAssertTrue(ok)
        // A target that reads file objects still gets the real folder.
        let readURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(readURLs, [folderURL])
        // A target that only reads plain text gets the POSIX path instead.
        XCTAssertEqual(pasteboard.string(forType: .string), folderURL.path)
    }

    func testMultipleFilesRestoreJoinsPathsAsText() throws {
        let fileA = tempDir.appendingPathComponent("a.txt")
        let fileB = tempDir.appendingPathComponent("b.txt")
        try "a".write(to: fileA, atomically: true, encoding: .utf8)
        try "b".write(to: fileB, atomically: true, encoding: .utf8)

        let entry = makeFilesEntry(paths: [fileA.path, fileB.path])
        XCTAssertTrue(PasteboardRestore.restore(entry, to: pasteboard))

        XCTAssertEqual(pasteboard.string(forType: .string), "\(fileA.path)\n\(fileB.path)")
    }

    func testMissingFileFailsRestore() {
        let entry = makeFilesEntry(paths: [tempDir.appendingPathComponent("missing").path])
        XCTAssertFalse(PasteboardRestore.restore(entry, to: pasteboard))
    }
}
