import Foundation

enum ClipboardItemType: String, Codable, CaseIterable {
    case text
    case image
    case files
}

enum RichTextFormat: String, Codable {
    case rtf
    case html
}
