import Combine
import XCTest

@MainActor
final class HistoryViewModelTests: XCTestCase {
    func testSearchKeepsJapaneseCaseInsensitiveAndOCRSemantics() async {
        let text = ClipboardEntry(type: .text, preview: "メモ", payload: "Hello 日本語")
        let image = ClipboardEntry(type: .image, preview: "画像", payload: "/tmp/secret.png", ocrText: "日本語の認識結果")
        let model = HistoryViewModel(fetchEntries: { $0([text, image]) })
        await load(model)

        model.searchText = "  HELLO  "
        XCTAssertEqual(model.visibleEntries.map(\.id), [text.id])
        model.searchText = "日本語"
        XCTAssertEqual(model.visibleEntries.map(\.id), [text.id, image.id])
        model.typeFilter = .image
        XCTAssertEqual(model.visibleEntries.map(\.id), [image.id])
        model.searchText = "secret"
        XCTAssertTrue(model.visibleEntries.isEmpty, "stored image paths must not be searchable")
        model.searchText = "画像"
        XCTAssertEqual(model.visibleEntries.map(\.id), [image.id])
        model.searchText = " "
        model.typeFilter = .all
        XCTAssertEqual(model.visibleEntries.map(\.id), [text.id, image.id])
    }

    func testSelectionAndMultiSelectionFollowFilteredOrder() async {
        let entries = (0..<4).map { ClipboardEntry(type: .text, preview: "item \($0)", payload: "item \($0)") }
        let model = HistoryViewModel(fetchEntries: { $0(entries) })
        await load(model)
        model.selectNext()
        model.selectNext()
        XCTAssertEqual(model.selectedEntry?.id, entries[2].id)
        model.toggleMultiSelection(entry: entries[2])
        model.toggleMultiSelection(entry: entries[0])
        XCTAssertEqual(model.multiSelectedEntries.map(\.id), [entries[0].id, entries[2].id])
        model.searchText = "item 2"
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.selectedEntry?.id, entries[2].id)
        XCTAssertEqual(model.multiSelectedEntries.map(\.id), [entries[2].id])
        model.searchText = "missing"
        model.selectNext()
        model.selectPrevious()
        XCTAssertNil(model.selectedEntry)
    }

    func testLiveRefreshInvalidatesSearchAndPreservesSelection() async {
        let first = ClipboardEntry(type: .text, preview: "first", payload: "first")
        let selected = ClipboardEntry(type: .text, preview: "selected", payload: "selected")
        var entries = [first, selected]
        let model = HistoryViewModel(fetchEntries: { $0(entries) })
        await load(model)
        model.selectNext()
        model.toggleMultiSelection(entry: first)
        model.beginEditing(entry: first)
        model.selectNext()
        _ = model.visibleEntries

        entries = [selected, ClipboardEntry(type: .text, preview: "new", payload: "new")]
        await historyChange(model)
        XCTAssertEqual(model.selectedEntry?.id, selected.id)
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertTrue(model.multiSelectedIds.isEmpty)
        XCTAssertFalse(model.isEditing)
        XCTAssertEqual(model.visibleEntries.map(\.id), entries.map(\.id))

        model.searchText = "recognized"
        XCTAssertTrue(model.visibleEntries.isEmpty)
        let image = ClipboardEntry(type: .image, preview: "image", payload: "/tmp/a.png", ocrText: "recognized")
        entries.append(image)
        await historyChange(model)
        XCTAssertEqual(model.visibleEntries.map(\.id), [image.id])
    }

    func testHiddenPanelDefersFetchingUntilReopened() async {
        var fetchCount = 0
        var entries = [ClipboardEntry(type: .text, preview: "before", payload: "before")]
        let model = HistoryViewModel(fetchEntries: { completion in
            fetchCount += 1
            completion(entries)
        })
        await load(model)
        model.suspend()
        entries = [ClipboardEntry(type: .text, preview: "after", payload: "after")]
        let unexpected = expectation(description: "hidden panel must not publish a refetch")
        unexpected.isInverted = true
        let subscription = model.$allEntries.dropFirst().sink { _ in unexpected.fulfill() }
        for _ in 0..<10 {
            NotificationCenter.default.post(name: .clipxsHistoryDidChange, object: nil)
        }
        await fulfillment(of: [unexpected], timeout: 0.1)
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(fetchCount, 1)
        await load(model)
        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(model.visibleEntries.first?.payload, "after")
    }

    func testEditsAndOCRWithUnchangedIDsInvalidateCachedResults() async {
        let textID = UUID()
        let imageID = UUID()
        var entries = [
            ClipboardEntry(id: textID, type: .text, preview: "before", payload: "before"),
            ClipboardEntry(id: imageID, type: .image, preview: "image", payload: "/tmp/a.png")
        ]
        let model = HistoryViewModel(fetchEntries: { $0(entries) })
        await load(model)
        model.searchText = "after"
        XCTAssertTrue(model.visibleEntries.isEmpty)
        entries = [
            ClipboardEntry(id: textID, type: .text, preview: "after", payload: "after"),
            ClipboardEntry(id: imageID, type: .image, preview: "image", payload: "/tmp/a.png", ocrText: "after")
        ]
        await historyChange(model)
        XCTAssertEqual(model.visibleEntries.map(\.id), [textID, imageID])
        model.typeFilter = .image
        XCTAssertEqual(model.visibleEntries.map(\.id), [imageID])
    }

    func testNotificationBurstCoalescesInflightFetches() async {
        var completions: [([ClipboardEntry]) -> Void] = []
        let model = HistoryViewModel(fetchEntries: { completions.append($0) })
        model.reload()
        XCTAssertEqual(completions.count, 1)
        for _ in 0..<10 {
            NotificationCenter.default.post(name: .clipxsHistoryDidChange, object: nil)
        }
        await drainMainActor()
        XCTAssertEqual(completions.count, 1)
        completions[0]([])
        await drainMainActor()
        XCTAssertEqual(completions.count, 2, "changes during a fetch need exactly one follow-up")
        completions[1]([])
        await drainMainActor()
        XCTAssertEqual(completions.count, 2)
    }

    func testCompletionAfterHideCannotOverwriteReopenedHistory() async {
        var completions: [([ClipboardEntry]) -> Void] = []
        let model = HistoryViewModel(fetchEntries: { completions.append($0) })
        model.reload()
        model.suspend()
        model.reload()
        XCTAssertEqual(completions.count, 2)
        let latest = ClipboardEntry(type: .text, preview: "latest", payload: "latest")
        completions[1]([latest])
        await drainMainActor()
        completions[0]([ClipboardEntry(type: .text, preview: "stale", payload: "stale")])
        await drainMainActor()
        XCTAssertEqual(model.visibleEntries.map(\.id), [latest.id])
    }

    func testSelectionChangedDuringFetchIsPreserved() async {
        let entries = (0..<3).map { ClipboardEntry(type: .text, preview: "item \($0)", payload: "item \($0)") }
        var completion: (([ClipboardEntry]) -> Void)?
        let model = HistoryViewModel(fetchEntries: { completion = $0 })
        model.reload()
        completion?(entries)
        await drainMainActor()
        model.reload()
        model.selectNext()
        model.selectNext()
        completion?(Array(entries.reversed()))
        await drainMainActor()
        XCTAssertEqual(model.selectedEntry?.id, entries[2].id)
        XCTAssertEqual(model.selectedIndex, 0)
    }

    private func load(_ model: HistoryViewModel) async {
        let loaded = expectation(description: "history loaded")
        let subscription = model.$allEntries.dropFirst().prefix(1).sink { _ in loaded.fulfill() }
        model.reload()
        await fulfillment(of: [loaded], timeout: 5)
        withExtendedLifetime(subscription) {}
    }

    private func historyChange(_ model: HistoryViewModel) async {
        let changed = expectation(description: "history changed")
        let subscription = model.$allEntries.dropFirst().prefix(1).sink { _ in changed.fulfill() }
        NotificationCenter.default.post(name: .clipxsHistoryDidChange, object: nil)
        await fulfillment(of: [changed], timeout: 5)
        withExtendedLifetime(subscription) {}
    }

    private func drainMainActor() async {
        let drained = expectation(description: "queued main actor tasks completed")
        Task { @MainActor in drained.fulfill() }
        await fulfillment(of: [drained], timeout: 5)
    }
}
