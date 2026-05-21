import AppKit
import Combine
import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var entries: [ClipboardEntry] = []
    @Published var selectedIndex: Int = 0

    var onPaste: ((ClipboardEntry) -> Void)?
    var onDismiss: (() -> Void)?

    func reload() {
        ClipboardStore.shared.fetchAll { [weak self] entries in
            Task { @MainActor in
                self?.entries = entries
                self?.selectedIndex = 0
            }
        }
    }

    func selectNext() {
        guard !entries.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, entries.count - 1)
    }

    func selectPrevious() {
        guard !entries.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func pasteSelected() {
        guard entries.indices.contains(selectedIndex) else { return }
        onPaste?(entries[selectedIndex])
    }

    func paste(entry: ClipboardEntry) {
        onPaste?(entry)
    }

    func dismiss() {
        onDismiss?()
    }
}
