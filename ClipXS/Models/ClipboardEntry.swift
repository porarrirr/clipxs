import Foundation

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
              let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }

        guard paths.allSatisfy({ !$0.isEmpty && ($0 as NSString).isAbsolutePath }) else {
            return []
        }
        return paths.map { URL(fileURLWithPath: $0) }
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
