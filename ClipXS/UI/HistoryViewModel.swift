import AppKit
import Combine
import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var allEntries: [ClipboardEntry] = [] {
        didSet { invalidateTypeFilter() }
    }
    @Published var selectedIndex: Int = 0
    /// Recreate the list's scroll state on every panel presentation, even when
    /// the selection was already at zero and emits no SwiftUI onChange.
    @Published private(set) var presentationID = UUID()

    /// ⌘クリックで作る複数選択。結合貼り付け・キュー投入の対象。
    @Published var multiSelectedIds: Set<UUID> = []

    /// In-panel editing of a text entry's content.
    @Published var editingEntryId: UUID?
    @Published var editingText: String = ""

    @Published var searchText: String = "" {
        didSet {
            if searchText != oldValue {
                cachedVisibleEntries = nil
                selectedIndex = 0
            }
        }
    }

    @Published var typeFilter: TypeFilter = .all {
        didSet {
            if typeFilter != oldValue {
                invalidateTypeFilter()
                selectedIndex = 0
            }
        }
    }

    var onPaste: ((ClipboardEntry, _ plainTextOnly: Bool) -> Void)?
    var onDismiss: (() -> Void)?

    private var historyObserver: NSObjectProtocol?
    private let fetchEntries: (@escaping ([ClipboardEntry]) -> Void) -> Void
    private var cachedTypeEntries: [ClipboardEntry]?
    private var cachedVisibleEntries: [ClipboardEntry]?
    private var isActive = false
    private var refreshID: UUID?
    private var needsRefresh = false

    init(fetchEntries: @escaping (@escaping ([ClipboardEntry]) -> Void) -> Void = ClipboardStore.shared.fetchAll) {
        self.fetchEntries = fetchEntries
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
        if let cachedVisibleEntries { return cachedVisibleEntries }

        // Search edits reuse classification (including file JSON/UTType work).
        // Selection and SwiftUI redraws reuse the entire result until an input
        // changes. With no filters, share the original array's storage.
        let typed: [ClipboardEntry]
        if let cachedTypeEntries {
            typed = cachedTypeEntries
        } else {
            typed = typeFilter == .all ? allEntries : allEntries.filter(typeFilter.matches)
            cachedTypeEntries = typed
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let result = query.isEmpty ? typed : typed.filter { matchesSearch($0, query: query) }
        cachedVisibleEntries = result
        return result
    }

    private func invalidateTypeFilter() {
        cachedTypeEntries = nil
        cachedVisibleEntries = nil
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
        isActive = true
        searchText = ""
        typeFilter = .all
        selectedIndex = 0
        multiSelectedIds = []
        cancelEditing()
        presentationID = UUID()
        refreshFromStore(resetToFirst: true)
    }

    /// The store keeps capturing while the panel is hidden. The next reload
    /// fetches the current snapshot, so hidden views need no database reads.
    func suspend() {
        isActive = false
        refreshID = nil
        needsRefresh = false
    }

    /// Refetch that preserves search, filter, and (when possible) the selection.
    /// Runs on every history change so an open panel updates live.
    private func refreshFromStore(resetToFirst: Bool = false) {
        guard isActive else { return }
        guard refreshID == nil else {
            needsRefresh = true
            return
        }
        let requestID = UUID()
        refreshID = requestID
        fetchEntries { [weak self] entries in
            Task { @MainActor in
                guard let self, self.isActive, self.refreshID == requestID else { return }
                // The user may have navigated while the fetch was running.
                // Opening should select the newest snapshot's first row, not
                // follow the previous snapshot's first row down the list.
                // Still honor keyboard navigation during the asynchronous fetch.
                let selectedId = resetToFirst && self.selectedIndex == 0
                    ? nil : self.selectedEntry?.id
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
                self.refreshID = nil
                if self.needsRefresh {
                    self.needsRefresh = false
                    self.refreshFromStore()
                }
            }
        }
    }

    private func matchesSearch(_ entry: ClipboardEntry, query: String) -> Bool {
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
