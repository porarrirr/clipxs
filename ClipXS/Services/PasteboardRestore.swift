import AppKit
import Foundation
import UniformTypeIdentifiers

enum PasteboardRestore {
    @discardableResult
    static func restore(
        _ entry: ClipboardEntry,
        plainTextOnly: Bool = false,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        // Load and validate everything before touching the destination clipboard.
        guard let items = makeItems(entry, plainTextOnly: plainTextOnly), !items.isEmpty else { return false }
        return replaceContents(items, on: pasteboard)
    }

    static func replaceContents(
        _ items: [NSPasteboardItem],
        on pasteboard: NSPasteboard,
        write: (NSPasteboard, [NSPasteboardItem]) -> Bool = { $0.writeObjects($1) }
    ) -> Bool {
        let previous: [NSPasteboardItem] = pasteboard.pasteboardItems?.map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        pasteboard.clearContents()
        guard write(pasteboard, items) else {
            pasteboard.clearContents()
            if !previous.isEmpty { pasteboard.writeObjects(previous) }
            return false
        }
        return true
    }

    private static func makeItems(_ entry: ClipboardEntry, plainTextOnly: Bool) -> [NSPasteboardItem]? {
        switch entry.type {
        case .text:
            return [textItem(entry.payload, rich: plainTextOnly ? nil : entry.richPayload, format: entry.richFormat)]
        case .image:
            guard let image = NSImage(contentsOfFile: entry.payload),
                  let item = imageItem(image) else { return nil }
            return [item]
        case .files:
            let urls = entry.fileURLs
            guard !urls.isEmpty,
                  urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
            if let parts = entry.preservedParts {
                let paths = parts.compactMap { part -> String? in
                    if case let .file(path) = part { return path }
                    return nil
                }
                guard paths == urls.map(\.path) else { return nil }
                var items: [NSPasteboardItem] = []
                for part in parts {
                    switch part {
                    case let .file(path):
                        items.append(fileItem(URL(fileURLWithPath: path)))
                    case let .text(plain, rich, format):
                        items.append(textItem(plain, rich: plainTextOnly ? nil : rich, format: format))
                    case let .image(png):
                        guard let image = NSImage(data: png), let item = imageItem(image) else { return nil }
                        items.append(item)
                    }
                }
                return items
            }
            // Ordinary files and folders are attachments too. Paths are only
            // emitted by the explicit "Paste File Paths" action.
            return urls.map(fileItem)
        }
    }

    private static func textItem(_ text: String, rich: Data?, format: RichTextFormat?) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if let rich, let format { item.setData(rich, forType: format == .rtf ? .rtf : .html) }
        return item
    }

    private static func imageItem(_ image: NSImage) -> NSPasteboardItem? {
        guard let tiff = image.tiffRepresentation else { return nil }
        let item = NSPasteboardItem()
        item.setData(tiff, forType: .tiff)
        if let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
        }
        return item
    }

    private static func fileItem(_ url: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
           let image = NSImage(contentsOf: url), let pixels = imageItem(image) {
            for type in pixels.types {
                if let data = pixels.data(forType: type) { item.setData(data, forType: type) }
            }
        }
        return item
    }
}
