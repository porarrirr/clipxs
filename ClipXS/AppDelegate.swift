import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLoginManager.syncWithSystem()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Touch the store now so schema migration runs at a predictable point
        // (startup), not lazily on the first capture or panel open.
        _ = ClipboardStore.shared

        statusBarController = StatusBarController()

        ClipboardMonitor.shared.start()

        HotkeyManager.shared.register(
            onHotkey: {
                HistoryPanelController.shared.toggle()
            },
            onQueuePaste: {
                Task { @MainActor in
                    PasteQueue.shared.pasteNext()
                }
            }
        )

        if !PasteService.isAccessibilityTrusted(prompt: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.showWelcomeAccessibilityAlert()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
        ClipboardMonitor.shared.stop()
    }

    private func showWelcomeAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("welcome_title", comment: "")
        alert.informativeText = NSLocalizedString("welcome_message", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("open_settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("later", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
