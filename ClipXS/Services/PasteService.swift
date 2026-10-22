import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import UserNotifications

/// Captured before the nonactivating history panel borrows keyboard focus.
struct PasteTarget {
    let app: NSRunningApplication
    let window: AXUIElement?
    let element: AXUIElement?

    init(app: NSRunningApplication) {
        self.app = app
        let application = AXUIElementCreateApplication(app.processIdentifier)
        element = Self.readElement(application, kAXFocusedUIElementAttribute)
        window = element.flatMap { Self.readElement($0, kAXWindowAttribute) }
            ?? Self.readElement(application, kAXFocusedWindowAttribute)
    }

    private static func readElement(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    func isFocused() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            return false
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        if let window {
            guard let current = Self.readElement(application, kAXFocusedWindowAttribute),
                  CFEqual(window, current) else { return false }
        }
        if let element {
            guard let current = Self.readElement(application, kAXFocusedUIElementAttribute),
                  CFEqual(element, current) else { return false }
        }
        return true
    }

    func restoreFocus() {
        // Activating an already active app can select a different main window.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        if let window {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(
                AXUIElementCreateApplication(app.processIdentifier),
                kAXFocusedWindowAttribute as CFString, window
            )
        }
        if let element {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }
}

enum PasteService {
    static let generatedPasteMarker: Int64 = 0x4350585350415354
    private static let vKeyCode = CGKeyCode(kVK_ANSI_V)
    private static let clipxsBundleId = Bundle.main.bundleIdentifier ?? "com.clipxs.ClipXS"

    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func paste(
        entry: ClipboardEntry,
        targetApp: NSRunningApplication? = nil,
        savedTarget: PasteTarget? = nil,
        plainTextOnly: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        let target = savedTarget?.app ?? resolveTargetApp(preferred: targetApp)

        guard let target, !target.isTerminated else {
            showNoTargetAlert()
            completion?(false)
            return
        }

        performPaste(entry: entry, into: savedTarget ?? PasteTarget(app: target), plainTextOnly: plainTextOnly, completion: completion)
    }

    private static func resolveTargetApp(preferred: NSRunningApplication?) -> NSRunningApplication? {
        if let preferred,
           preferred.bundleIdentifier != clipxsBundleId,
           !preferred.isTerminated {
            return preferred
        }

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != clipxsBundleId,
           !front.isTerminated {
            return front
        }

        return nil
    }

    private static func performPaste(
        entry: ClipboardEntry,
        into destination: PasteTarget,
        plainTextOnly: Bool,
        completion: ((Bool) -> Void)?
    ) {
        let target = destination.app
        let trusted = isAccessibilityTrusted(prompt: false)
        // Per-app rule: apps on the plain-paste list always receive plain text
        // (terminals, editors where rich formatting is unwanted).
        let forcePlain = entry.type == .text
            && SettingsAccess.plainPasteBundleIds.contains(target.bundleIdentifier ?? "")
        let restored = ClipboardMonitor.shared.performWithoutCapture {
            PasteboardRestore.restore(entry, plainTextOnly: plainTextOnly || forcePlain)
        }
        guard restored else {
            showPasteFailedAlert()
            completion?(false)
            return
        }

        // Let orderOut return keyboard focus before deciding whether restoration
        // is needed. Never reorder every window of the destination application.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitUntilFocused(destination, attempts: 15) { focused in
                guard focused else {
                    showManualPasteNotification()
                    completion?(false)
                    return
                }
                // Check the exact process, window and input immediately before
                // emitting the global shortcut; app identity alone is insufficient.
                if trusted, destination.isFocused(), postCommandV() {
                    // Posting an event is asynchronous. Keep the clipboard stable
                    // while the destination handles it before advancing the queue.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        completion?(true)
                    }
                } else {
                    showManualPasteNotification()
                    completion?(false)
                }
            }
        }
    }

    private static func waitUntilFocused(
        _ target: PasteTarget,
        attempts: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard !target.app.isTerminated else {
            completion(false)
            return
        }
        if target.isFocused() {
            completion(true)
            return
        }
        guard attempts > 0 else {
            completion(false)
            return
        }
        target.restoreFocus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            waitUntilFocused(target, attempts: attempts - 1, completion: completion)
        }
    }

    private static func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
            ?? CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return false }

        keyDown.setIntegerValueField(.eventSourceUserData, value: generatedPasteMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: generatedPasteMarker)
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func showNoTargetAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("no_target_title", comment: "")
        alert.informativeText = NSLocalizedString("no_target_message", comment: "")
        alert.alertStyle = .informational
        alert.runModal()
    }

    private static func showManualPasteNotification() {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("manual_paste_title", comment: "")
        content.body = NSLocalizedString("manual_paste_body", comment: "")
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func showPasteFailedAlert() {
        requestNotificationPermissionIfNeeded()

        let appPath = Bundle.main.bundleURL.path
        let trusted = isAccessibilityTrusted(prompt: false)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("accessibility_title", comment: "")
        if trusted {
            alert.informativeText = String(
                format: NSLocalizedString("paste_failed_message", comment: ""),
                appPath
            ) + "\n\n" + NSLocalizedString("manual_paste_body", comment: "")
        } else {
            alert.informativeText = String(
                format: NSLocalizedString("accessibility_message", comment: ""),
                appPath
            )
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("open_settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("restart_app", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("cancel", comment: ""))

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            relaunch()
        default:
            break
        }
    }

    private static func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func relaunch() {
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
