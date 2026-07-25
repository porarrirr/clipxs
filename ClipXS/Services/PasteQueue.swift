import AppKit
import Combine
import Foundation

/// Pastebot-style paste queue: entries added from the panel are pasted in
/// order, one per press of the queue hotkey (panel hotkey + Shift), into the
/// frontmost app.
@MainActor
final class PasteQueue: ObservableObject {
    static let shared = PasteQueue()

    @Published private(set) var entries: [ClipboardEntry] = []
    /// Serializes hotkey presses: a second press while a paste is in flight
    /// would race the frontmost-app activation dance in PasteService.
    private var isPasting = false

    private init() {}

    func enqueue(_ newEntries: [ClipboardEntry]) {
        entries.append(contentsOf: newEntries)
    }

    func clear() {
        entries = []
    }

    func pasteNext() {
        guard !isPasting, let next = entries.first else { return }
        isPasting = true
        PasteService.paste(entry: next) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                self.isPasting = false
                // Keep the entry on failure so nothing is silently dropped.
                if success, self.entries.first?.id == next.id {
                    self.entries.removeFirst()
                }
            }
        }
    }
}
