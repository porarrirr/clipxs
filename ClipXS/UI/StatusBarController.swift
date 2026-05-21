import AppKit

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let launchAtLoginItem = NSMenuItem()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        if let button = statusItem.button {
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipXS")
            }
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func configureMenu() {
        let openItem = NSMenuItem(
            title: NSLocalizedString("menu_open_history", comment: ""),
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        openItem.target = self

        let clearItem = NSMenuItem(
            title: NSLocalizedString("menu_clear_history", comment: ""),
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearItem.target = self

        let accessibilityItem = NSMenuItem(
            title: NSLocalizedString("menu_accessibility", comment: ""),
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self

        launchAtLoginItem.title = NSLocalizedString("menu_launch_at_login", comment: "")
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        launchAtLoginItem.target = self
        updateLaunchAtLoginItemState()

        let quitItem = NSMenuItem(
            title: NSLocalizedString("menu_quit", comment: ""),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self

        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(clearItem)
        menu.addItem(accessibilityItem)
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = nil
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            HistoryPanelController.shared.toggle()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            statusItem.popUpMenu(menu)
        } else {
            HistoryPanelController.shared.toggle()
        }
    }

    @objc private func openHistory() {
        HistoryPanelController.shared.show()
    }

    @objc private func clearHistory() {
        ClipboardStore.shared.clearAll {
            NotificationCenter.default.post(name: .clipxsHistoryDidChange, object: nil)
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let newValue = !LaunchAtLoginManager.isEnabled
        if LaunchAtLoginManager.setEnabled(newValue) {
            updateLaunchAtLoginItemState()
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("launch_at_login_failed_title", comment: "")
        alert.informativeText = NSLocalizedString("launch_at_login_failed_message", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("open_login_items_settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("cancel", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
        updateLaunchAtLoginItemState()
    }

    private func updateLaunchAtLoginItemState() {
        LaunchAtLoginManager.syncWithSystem()
        launchAtLoginItem.state = LaunchAtLoginManager.isEnabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let clipxsHistoryDidChange = Notification.Name("clipxsHistoryDidChange")
}
