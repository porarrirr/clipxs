import Foundation

enum TypeFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case link
    case image
    case file

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "filter_all"
        case .text: return "filter_text"
        case .link: return "filter_link"
        case .image: return "filter_image"
        case .file: return "filter_file"
        }
    }

    func matches(_ entry: ClipboardEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return entry.type == .text && !entry.isLink
        case .link:
            return entry.isLink
        case .image:
            return entry.isImageForDisplay
        case .file:
            return entry.type == .files && !entry.isImageForDisplay
        }
    }
}
