import AppKit
import XCTest

final class ThumbnailLoaderTests: XCTestCase {
    func testGeneratesNonEmptyQuickLookThumbnailForPNG() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipXSTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let pngURL = directory.appendingPathComponent("quick-look.png")
        try XCTUnwrap(makePNGData()).write(to: pngURL)

        let thumbnail = try await ThumbnailLoader.quickLookThumbnail(
            for: pngURL,
            size: CGSize(width: 80, height: 80),
            scale: 2
        )

        XCTAssertGreaterThan(thumbnail.size.width, 0)
        XCTAssertGreaterThan(thumbnail.size.height, 0)
        XCTAssertFalse(try XCTUnwrap(thumbnail.tiffRepresentation).isEmpty)
    }

    private func makePNGData() -> Data? {
        let image = NSImage(size: NSSize(width: 32, height: 24))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 24).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
