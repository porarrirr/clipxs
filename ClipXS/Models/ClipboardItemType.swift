import Foundation

enum ClipboardItemType: String, Codable, CaseIterable {
    case text
    case image
    case files
}
