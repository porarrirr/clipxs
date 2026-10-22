import AppKit
import Foundation

final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

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

    /// Account for our synchronous clipboard write, including a failed write
    /// rolled back by PasteboardRestore. Never suppress the user's next copy.
    @discardableResult
    func performWithoutCapture(_ write: () -> Bool) -> Bool {
        defer { lastChangeCount = NSPasteboard.general.changeCount }
        return write()
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        // Frontmost app at poll time is the best available guess at the copy's
        // source (the 0.5s polling window makes this a heuristic).
        let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleId, SettingsAccess.excludedBundleIds.contains(sourceBundleId) {
            return
        }

        guard let captured = PasteboardCapture.capture(from: pasteboard, sourceBundleId: sourceBundleId) else { return }
        ClipboardStore.shared.insert(captured)

        if captured.entry.type == .image,
           let imageData = captured.imageData,
           SettingsAccess.ocrEnabled {
            let entryId = captured.entry.id
            OCRService.recognizeText(in: imageData) { text in
                guard let text, !text.isEmpty else { return }
                ClipboardStore.shared.updateOCRText(id: entryId, text: text)
            }
        }
    }
}
