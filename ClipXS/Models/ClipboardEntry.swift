import Foundation

struct ClipboardEntry: Identifiable, Equatable, Hashable {
    let id: UUID
    let type: ClipboardItemType
    let preview: String
    let payload: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        preview: String,
        payload: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.preview = preview
        self.payload = payload
        self.createdAt = createdAt
    }
}
