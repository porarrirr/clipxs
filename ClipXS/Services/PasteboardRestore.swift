import AppKit
import Foundation

enum PasteboardRestore {
    @discardableResult
    static func restore(
        _ entry: ClipboardEntry,
        plainTextOnly: Bool = false,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        pasteboard.clearContents()

        switch entry.type {
        case .text:
            if !plainTextOnly,
               let rich = entry.richPayload,
               let format = entry.richFormat {
                let richType: NSPasteboard.PasteboardType = format == .rtf ? .rtf : .html
                pasteboard.declareTypes([richType, .string], owner: nil)
                if pasteboard.setData(rich, forType: richType),
                   pasteboard.setString(entry.payload, forType: .string) {
                    return true
                }
                pasteboard.clearContents()
            }
            return pasteboard.setString(entry.payload, forType: .string)
        case .image:
            guard let image = NSImage(contentsOfFile: entry.payload) else { return false }
            return pasteboard.writeObjects([image])
        case .files:
            let urls = entry.fileURLs
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return false }

            var wroteFileObjects = pasteboard.writeObjects(urls as [NSURL])
            if !wroteFileObjects {
                let items: [NSPasteboardItem] = urls.map { url in
                    let item = NSPasteboardItem()
                    item.setString(url.absoluteString, forType: .fileURL)
                    item.setString(url.path, forType: .legacyFilenames)
                    return item
                }
                wroteFileObjects = pasteboard.writeObjects(items)
            }

            // Targets that only accept plain text (text fields, terminals) have
            // no file-object type to read; add the POSIX path as text on the
            // same pasteboard item so paste still succeeds there, alongside the
            // real file object for targets that do support it.
            let pathText = urls.map(\.path).joined(separator: "\n")
            let wroteText = pasteboard.setString(pathText, forType: .string)

            return wroteFileObjects || wroteText
        }
    }
}

private extension NSPasteboard.PasteboardType {
    static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
}
