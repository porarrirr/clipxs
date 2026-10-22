import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("settings_title", comment: "")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        // LSUIElement apps do not activate on their own; without this the
        // window would open behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
