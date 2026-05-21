import AppKit
import Foundation

enum PasteboardRestore {
    @discardableResult
    static func restore(_ entry: ClipboardEntry, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()

        switch entry.type {
        case .text:
            return pasteboard.setString(entry.payload, forType: .string)
        case .image:
            guard let image = NSImage(contentsOfFile: entry.payload) else { return false }
            return pasteboard.writeObjects([image])
        case .files:
            guard let data = entry.payload.data(using: .utf8),
                  let paths = try? JSONDecoder().decode([String].self, from: data)
            else { return false }
            let urls = paths
                .map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return false }

            if pasteboard.writeObjects(urls as [NSURL]) {
                return true
            }

            let items: [NSPasteboardItem] = urls.map { url in
                let item = NSPasteboardItem()
                item.setString(url.absoluteString, forType: .fileURL)
                item.setString(url.path, forType: .legacyFilenames)
                return item
            }
            return pasteboard.writeObjects(items)
        }
    }
}

private extension NSPasteboard.PasteboardType {
    static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
}
