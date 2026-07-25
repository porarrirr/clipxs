import AppKit
import Combine
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
        case .all: return true
        case .text: return entry.type == .text && !entry.isLink
        case .link: return entry.isLink
        case .image: return entry.type == .image
        case .file: return entry.type == .files
        }
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var allEntries: [ClipboardEntry] = []
    @Published var selectedIndex: Int = 0

    /// ⌘クリックで作る複数選択。結合貼り付け・キュー投入の対象。
    @Published var multiSelectedIds: Set<UUID> = []

    /// In-panel editing of a text entry's content.
    @Published var editingEntryId: UUID?
    @Published var editingText: String = ""

    @Published var searchText: String = "" {
        didSet { if searchText != oldValue { selectedIndex = 0 } }
    }

    @Published var typeFilter: TypeFilter = .all {
        didSet { if typeFilter != oldValue { selectedIndex = 0 } }
    }

    var onPaste: ((ClipboardEntry, _ plainTextOnly: Bool) -> Void)?
    var onDismiss: (() -> Void)?

    private var historyObserver: NSObjectProtocol?

    init() {
        historyObserver = NotificationCenter.default.addObserver(
            forName: .clipxsHistoryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromStore()
            }
        }
    }

    deinit {
        if let historyObserver {
            NotificationCenter.default.removeObserver(historyObserver)
        }
    }

    var visibleEntries: [ClipboardEntry] {
        allEntries.filter { typeFilter.matches($0) && matchesSearch($0) }
    }

    var selectedEntry: ClipboardEntry? {
        let visible = visibleEntries
        guard visible.indices.contains(selectedIndex) else { return nil }
        return visible[selectedIndex]
    }

    var isEditing: Bool {
        editingEntryId != nil
    }

    /// Multi-selected entries in visible (display) order.
    var multiSelectedEntries: [ClipboardEntry] {
        visibleEntries.filter { multiSelectedIds.contains($0.id) }
    }

    /// Full reset used when the panel opens.
    func reload() {
        searchText = ""
        typeFilter = .all
        selectedIndex = 0
        multiSelectedIds = []
        cancelEditing()
        refreshFromStore()
    }

    /// Refetch that preserves search, filter, and (when possible) the selection.
    /// Runs on every history change so an open panel updates live.
    private func refreshFromStore() {
        let selectedId = selectedEntry?.id
        ClipboardStore.shared.fetchAll { [weak self] entries in
            Task { @MainActor in
                guard let self else { return }
                self.allEntries = entries
                let visible = self.visibleEntries
                if let selectedId,
                   let index = visible.firstIndex(where: { $0.id == selectedId }) {
                    self.selectedIndex = index
                } else {
                    self.selectedIndex = visible.isEmpty
                        ? 0
                        : self.selectedIndex.clamped(to: 0...(visible.count - 1))
                }
                let ids = Set(entries.map(\.id))
                self.multiSelectedIds = self.multiSelectedIds.intersection(ids)
                if let editingEntryId = self.editingEntryId, !ids.contains(editingEntryId) {
                    self.cancelEditing()
                }
            }
        }
    }

    private func matchesSearch(_ entry: ClipboardEntry) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        if entry.preview.localizedCaseInsensitiveContains(query) {
            return true
        }
        // Image payloads are opaque file paths; searching them only produces
        // noise — but their recognized (OCR) text is searchable.
        if entry.type != .image, entry.payload.localizedCaseInsensitiveContains(query) {
            return true
        }
        if let ocrText = entry.ocrText, ocrText.localizedCaseInsensitiveContains(query) {
            return true
        }
        return false
    }

    // MARK: - Selection

    func selectNext() {
        let count = visibleEntries.count
        guard count > 0 else { return }
        selectedIndex = min(selectedIndex + 1, count - 1)
    }

    func selectPrevious() {
        guard !visibleEntries.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func toggleMultiSelection(entry: ClipboardEntry) {
        if multiSelectedIds.contains(entry.id) {
            multiSelectedIds.remove(entry.id)
        } else {
            multiSelectedIds.insert(entry.id)
        }
    }

    func clearMultiSelection() {
        multiSelectedIds = []
    }

    // MARK: - Actions

    func pasteSelected(plainTextOnly: Bool = false) {
        guard let entry = selectedEntry else { return }
        onPaste?(entry, plainTextOnly)
    }

    func paste(entry: ClipboardEntry, plainTextOnly: Bool = false) {
        onPaste?(entry, plainTextOnly)
    }

    /// Pastes the nth visible item (0-based), for the ⌘1–⌘9 shortcuts.
    func paste(at index: Int) {
        let visible = visibleEntries
        guard visible.indices.contains(index) else { return }
        onPaste?(visible[index], false)
    }

    /// Pastes the entry's text run through a filter, always as plain text.
    /// The stored entry itself is left untouched.
    func pasteTransformed(entry: ClipboardEntry, transform: TextTransform) {
        guard entry.type == .text else { return }
        let transformed = transform.apply(to: entry.payload)
        let ephemeral = ClipboardEntry(
            type: .text,
            preview: PasteboardCapture.textPreview(from: transformed),
            payload: transformed
        )
        onPaste?(ephemeral, true)
    }

    /// Pastes the image entry's recognized text as plain text.
    func pasteOCRText(entry: ClipboardEntry) {
        guard let ocrText = entry.ocrText, !ocrText.isEmpty else { return }
        let ephemeral = ClipboardEntry(
            type: .text,
            preview: PasteboardCapture.textPreview(from: ocrText),
            payload: ocrText
        )
        onPaste?(ephemeral, true)
    }

    func copyOCRText(entry: ClipboardEntry) {
        guard let ocrText = entry.ocrText, !ocrText.isEmpty else { return }
        ClipboardMonitor.shared.suppressNextCapture()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ocrText, forType: .string)
    }

    // MARK: - Merge & queue

    /// Text representation used for merge paste; images have no text.
    private func mergeText(for entry: ClipboardEntry) -> String? {
        switch entry.type {
        case .text:
            return entry.payload
        case .files:
            guard let data = entry.payload.data(using: .utf8),
                  let paths = try? JSONDecoder().decode([String].self, from: data)
            else { return nil }
            return paths.joined(separator: "\n")
        case .image:
            return nil
        }
    }

    var mergeableSelectionCount: Int {
        multiSelectedEntries.compactMap(mergeText(for:)).count
    }

    /// Joins the multi-selected entries (visible order) with newlines and
    /// pastes the result as plain text.
    func pasteMergedSelection() {
        let texts = multiSelectedEntries.compactMap(mergeText(for:))
        guard !texts.isEmpty else { return }
        let merged = texts.joined(separator: "\n")
        let ephemeral = ClipboardEntry(
            type: .text,
            preview: PasteboardCapture.textPreview(from: merged),
            payload: merged
        )
        clearMultiSelection()
        onPaste?(ephemeral, true)
    }

    /// Adds the multi-selection (or, when empty, the highlighted entry) to the
    /// paste queue in visible order.
    func enqueueSelection() {
        let targets = multiSelectedIds.isEmpty
            ? selectedEntry.map { [$0] } ?? []
            : multiSelectedEntries
        guard !targets.isEmpty else { return }
        PasteQueue.shared.enqueue(targets)
        clearMultiSelection()
    }

    func enqueue(entry: ClipboardEntry) {
        PasteQueue.shared.enqueue([entry])
    }

    // MARK: - Editing

    func beginEditing(entry: ClipboardEntry) {
        guard entry.type == .text else { return }
        editingText = entry.payload
        editingEntryId = entry.id
        if let index = visibleEntries.firstIndex(where: { $0.id == entry.id }) {
            selectedIndex = index
        }
    }

    func beginEditingSelected() {
        guard let entry = selectedEntry else { return }
        beginEditing(entry: entry)
    }

    func commitEditing() {
        guard let editingEntryId else { return }
        let text = editingText
        cancelEditing()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ClipboardStore.shared.updateText(id: editingEntryId, newText: text)
    }

    func cancelEditing() {
        editingEntryId = nil
        editingText = ""
    }

    // MARK: - Delete / pin / copy

    func deleteSelected() {
        guard let entry = selectedEntry else { return }
        delete(entry: entry)
    }

    func delete(entry: ClipboardEntry) {
        ClipboardStore.shared.deleteEntry(entry)
    }

    func togglePin(entry: ClipboardEntry) {
        ClipboardStore.shared.setPinned(!entry.isPinned, id: entry.id)
    }

    func togglePinSelected() {
        guard let entry = selectedEntry else { return }
        togglePin(entry: entry)
    }

    /// Copies the entry back to the clipboard without pasting anywhere.
    func copyOnly(entry: ClipboardEntry) {
        ClipboardMonitor.shared.suppressNextCapture()
        PasteboardRestore.restore(entry)
    }

    func dismiss() {
        onDismiss?()
    }
}
