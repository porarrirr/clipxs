import Foundation
import UniformTypeIdentifiers

/// Separate pasteboard items, preserving order and each item's representation.
enum ClipboardPart: Codable, Equatable, Hashable {
    case file(path: String)
    case text(plain: String, rich: Data?, format: RichTextFormat?)
    case image(png: Data)

    var text: String? {
        if case let .text(plain, _, _) = self { return plain }
        return nil
    }
}

/// Older file entries remain JSON arrays of paths. Mixed entries use this
/// envelope in the same payload column, so no database migration is needed.
struct FileClipboardPayload: Codable {
    let paths: [String]
    let parts: [ClipboardPart]
}

struct ClipboardEntry: Identifiable, Equatable, Hashable {
    let id: UUID
    let type: ClipboardItemType
    let preview: String
    let payload: String
    let createdAt: Date
    let isPinned: Bool
    let richPayload: Data?
    let richFormat: RichTextFormat?
    /// Bundle ID of the app frontmost when the copy was captured, if known.
    let sourceBundleId: String?
    /// Text recognized inside an image entry (Vision OCR); nil until recognized.
    let ocrText: String?

    init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        preview: String,
        payload: String,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        richPayload: Data? = nil,
        richFormat: RichTextFormat? = nil,
        sourceBundleId: String? = nil,
        ocrText: String? = nil
    ) {
        self.id = id
        self.type = type
        self.preview = preview
        self.payload = payload
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.richPayload = richPayload
        self.richFormat = richFormat
        self.sourceBundleId = sourceBundleId
        self.ocrText = ocrText
    }

    /// Derived at display time so existing rows need no reclassification.
    var isLink: Bool {
        guard type == .text else { return false }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count < 2048,
              !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased()
        else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// File URLs decoded from the existing JSON payload, preserving its order.
    /// Relative and empty paths are rejected so malformed history rows cannot
    /// accidentally resolve against the app's working directory.
    var fileURLs: [URL] {
        guard type == .files,
              let data = payload.data(using: .utf8),
              let paths = (try? JSONDecoder().decode([String].self, from: data))
                ?? (try? JSONDecoder().decode(FileClipboardPayload.self, from: data).paths)
        else { return [] }

        guard paths.allSatisfy({ !$0.isEmpty && ($0 as NSString).isAbsolutePath }) else {
            return []
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    var preservedParts: [ClipboardPart]? {
        guard type == .files, let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FileClipboardPayload.self, from: data).parts
    }

    var accompanyingText: String {
        preservedParts?.compactMap(\.text).joined(separator: "\n") ?? ""
    }

    /// Display-only classification for Finder file payloads. The stored type
    /// remains `.files`, so pasting still restores file objects.
    var isImageForDisplay: Bool {
        if type == .image {
            return true
        }
        guard type == .files, preservedParts == nil, !fileURLs.isEmpty else {
            return false
        }
        return fileURLs.allSatisfy { url in
            guard let contentType = UTType(filenameExtension: url.pathExtension.lowercased()) else {
                return false
            }
            return contentType.conforms(to: .image)
        }
    }

    /// Preserve attachments as file objects; never turn image storage paths into text.
    /// Mixed text/attachment selections cannot be represented by one entry.
    static func merging(_ entries: [ClipboardEntry]) -> ClipboardEntry? {
        guard !entries.isEmpty, entries.allSatisfy({ $0.preservedParts == nil }) else { return nil }
        if entries.allSatisfy({ $0.type == .text }) {
            let text = entries.map(\.payload).joined(separator: "\n")
            return ClipboardEntry(type: .text, preview: String(text.prefix(200)), payload: text)
        }
        guard entries.allSatisfy({ $0.type != .text }) else { return nil }
        var paths: [String] = []
        for entry in entries {
            if entry.type == .image {
                guard !entry.payload.isEmpty, (entry.payload as NSString).isAbsolutePath else { return nil }
                paths.append(entry.payload)
            } else {
                let urls = entry.fileURLs
                guard !urls.isEmpty else { return nil }
                paths.append(contentsOf: urls.map(\.path))
            }
        }
        guard let data = try? JSONEncoder().encode(paths),
              let payload = String(data: data, encoding: .utf8) else { return nil }
        return ClipboardEntry(type: .files, preview: entries[0].preview, payload: payload)
    }

    func withPinned(_ pinned: Bool) -> ClipboardEntry {
        ClipboardEntry(
            id: id,
            type: type,
            preview: preview,
            payload: payload,
            createdAt: createdAt,
            isPinned: pinned,
            richPayload: richPayload,
            richFormat: richFormat,
            sourceBundleId: sourceBundleId,
            ocrText: ocrText
        )
    }
}
