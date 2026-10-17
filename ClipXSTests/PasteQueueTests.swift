import AppKit
import Carbon.HIToolbox
import XCTest

@MainActor
final class PasteQueueTests: XCTestCase {
    func testThreeItemsPasteInOrderAndEmptyQueueDoesNothing() async {
        var pasted: [UUID] = []
        let queue = PasteQueue(monitorsKeyboard: false) { entry, completion in
            pasted.append(entry.id)
            completion(true)
        }
        let entries = (1...3).map { ClipboardEntry(type: .text, preview: "\($0)", payload: "\($0)") }
        queue.enqueue(entries)
        for remaining in (0...2).reversed() {
            queue.pasteNext()
            await Task.yield()
            XCTAssertEqual(queue.entries.count, remaining)
        }
        queue.pasteNext()
        XCTAssertEqual(pasted, entries.map(\.id))
    }

    func testFailureKeepsItemAndRapidPressDoesNotSkipIt() async {
        var completions: [(Bool) -> Void] = []
        let queue = PasteQueue(monitorsKeyboard: false) { _, completion in
            completions.append(completion)
        }
        let entry = ClipboardEntry(type: .text, preview: "one", payload: "one")
        queue.enqueue([entry])
        queue.pasteNext()
        queue.pasteNext()
        XCTAssertEqual(completions.count, 1)
        completions[0](false)
        await Task.yield()
        XCTAssertEqual(queue.entries, [entry])
        queue.pasteNext()
        XCTAssertEqual(completions.count, 2)
        completions[1](true)
        await Task.yield()
        XCTAssertTrue(queue.entries.isEmpty)
    }

    func testClearDuringPasteDoesNotRemoveNewQueue() async {
        var finish: ((Bool) -> Void)?
        let queue = PasteQueue(monitorsKeyboard: false) { _, completion in finish = completion }
        let first = ClipboardEntry(type: .text, preview: "first", payload: "first")
        let second = ClipboardEntry(type: .text, preview: "second", payload: "second")
        queue.enqueue([first])
        queue.pasteNext()
        queue.clear()
        queue.enqueue([second])
        finish?(true)
        await Task.yield()
        XCTAssertEqual(queue.entries, [second])
    }

    func testRecognizesOnlyPlainCommandVAndControlVAndIgnoresGeneratedPaste() {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)!
        for flags: CGEventFlags in [.maskCommand, .maskControl, [.maskCommand, .maskAlphaShift]] {
            event.flags = flags
            XCTAssertTrue(PasteQueue.isPasteShortcut(event))
        }
        for flags: CGEventFlags in [[], .maskAlternate, [.maskCommand, .maskShift], [.maskControl, .maskCommand]] {
            event.flags = flags
            XCTAssertFalse(PasteQueue.isPasteShortcut(event))
        }
        event.flags = .maskCommand
        event.setIntegerValueField(.eventSourceUserData, value: PasteService.generatedPasteMarker)
        XCTAssertFalse(PasteQueue.isPasteShortcut(event), "Synthetic paste must not recurse into the queue")
        event.setIntegerValueField(.eventSourceUserData, value: 0)
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_ANSI_C))
        XCTAssertFalse(PasteQueue.isPasteShortcut(event))
    }
}
