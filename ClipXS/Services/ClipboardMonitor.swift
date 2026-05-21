import AppKit
import Foundation

final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    var onEntriesChanged: (() -> Void)?

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var ignoreNextChange = false

    private init() {}

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func suppressNextCapture() {
        ignoreNextChange = true
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        guard let captured = PasteboardCapture.capture(from: pasteboard) else { return }
        ClipboardStore.shared.insert(captured.entry, contentHash: captured.contentHash)
        onEntriesChanged?()
    }
}
