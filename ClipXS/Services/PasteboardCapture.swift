import AppKit
import CryptoKit
import Foundation

struct CapturedClipboardItem {
    let entry: ClipboardEntry
    let contentHash: String
    /// PNG data for image entries. Written to `entry.payload` by ClipboardStore
    /// on its serial queue, so file creation cannot race the orphan cleanup.
    let imageData: Data?

    init(entry: ClipboardEntry, contentHash: String, imageData: Data? = nil) {
        self.entry = entry
        self.contentHash = contentHash
        self.imageData = imageData
    }
}

enum PasteboardCapture {
    private static let previewLimit = 200

    static func capture(from pasteboard: NSPasteboard = .general) -> CapturedClipboardItem? {
        if let files = readFileURLs(from: pasteboard), !files.isEmpty {
            return makeFilesItem(urls: files)
        }
        if let imageItem = makeImageItem(from: pasteboard) {
            return imageItem
        }
        if let textItem = makeTextItem(from: pasteboard) {
            return textItem
        }
        return nil
    }

    private static func readFileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        guard pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return nil
        }
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL]
        let urls = objects?.compactMap { $0 as URL }.filter { $0.isFileURL } ?? []
        return urls.isEmpty ? nil : urls
    }

    private static func makeFilesItem(urls: [URL]) -> CapturedClipboardItem {
        let paths = urls.map(\.path)
        let payloadData = try? JSONEncoder().encode(paths)
        let payload = String(data: payloadData ?? Data(), encoding: .utf8) ?? "[]"
        let hash = sha256(payload)

        let firstName = urls.first?.lastPathComponent ?? ""
        let preview: String
        if urls.count == 1 {
            preview = firstName
        } else {
            preview = String(
                format: NSLocalizedString("files_preview_multiple", comment: ""),
                urls.count,
                firstName
            )
        }

        let entry = ClipboardEntry(type: .files, preview: preview, payload: payload)
        return CapturedClipboardItem(entry: entry, contentHash: hash)
    }

    private static func makeImageItem(from pasteboard: NSPasteboard) -> CapturedClipboardItem? {
        let pngData: Data?
        if let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            pngData = rep.representation(using: .png, properties: [:])
        } else if let data = pasteboard.data(forType: .png) {
            pngData = data
        } else if let data = pasteboard.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: data) {
            pngData = rep.representation(using: .png, properties: [:])
        } else {
            pngData = nil
        }

        guard let png = pngData else { return nil }

        let fileName = UUID().uuidString + ".png"
        let fileURL = ClipboardStore.shared.imagesDirectory.appendingPathComponent(fileName)
        let hash = sha256(png)
        let preview = NSLocalizedString("image_preview", comment: "")
        let entry = ClipboardEntry(type: .image, preview: preview, payload: fileURL.path)
        return CapturedClipboardItem(entry: entry, contentHash: hash, imageData: png)
    }

    private static func makeTextItem(from pasteboard: NSPasteboard) -> CapturedClipboardItem? {
        guard let text = pasteboard.string(forType: .string) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let preview = String(trimmed.prefix(previewLimit))
            .replacingOccurrences(of: "\n", with: " ")
        let hash = sha256(text)
        let entry = ClipboardEntry(type: .text, preview: preview, payload: text)
        return CapturedClipboardItem(entry: entry, contentHash: hash)
    }

    private static func sha256(_ value: String) -> String {
        sha256(Data(value.utf8))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
