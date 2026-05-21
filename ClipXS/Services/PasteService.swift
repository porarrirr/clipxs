import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import UserNotifications

enum PasteService {
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
        completion: ((Bool) -> Void)? = nil
    ) {
        ClipboardMonitor.shared.suppressNextCapture()
        let target = resolveTargetApp(preferred: targetApp)

        guard let target, !target.isTerminated else {
            showNoTargetAlert()
            completion?(false)
            return
        }

        performPaste(entry: entry, into: target, completion: completion)
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
        into target: NSRunningApplication,
        completion: ((Bool) -> Void)?
    ) {
        let trusted = isAccessibilityTrusted(prompt: false)
        guard PasteboardRestore.restore(entry) else {
            showPasteFailedAlert()
            completion?(false)
            return
        }

        target.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            guard ensureFrontmost(target) else {
                showManualPasteNotification()
                completion?(true)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                var succeeded = false

                if !succeeded, trusted {
                    succeeded = postCommandVGlobally()
                }

                if !succeeded, trusted {
                    succeeded = postCommandV(to: target.processIdentifier)
                }

                if !succeeded, trusted, entry.type == .text {
                    succeeded = insertTextViaAccessibility(entry.payload)
                }

                if !succeeded, trusted, entry.type == .text {
                    succeeded = typeTextViaKeyboardEvents(entry.payload)
                }

                if succeeded {
                    completion?(true)
                } else {
                    showManualPasteNotification()
                    showPasteFailedAlert()
                    completion?(false)
                }
            }
        }
    }

    @discardableResult
    private static func ensureFrontmost(_ target: NSRunningApplication, attempts: Int = 8) -> Bool {
        for _ in 0..<attempts {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target.bundleIdentifier {
                return true
            }
            target.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            Thread.sleep(forTimeInterval: 0.04)
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target.bundleIdentifier
    }

    private static func postCommandV(to pid: pid_t) -> Bool {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }

    private static func postCommandVGlobally() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
            ?? CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func typeTextViaKeyboardEvents(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        let source = CGEventSource(stateID: .hidSystemState)
            ?? CGEventSource(stateID: .combinedSessionState)

        for var codeUnit in text.utf16 {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return false }

            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }

        return true
    }

    private static func insertTextViaAccessibility(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }

        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success,
        let focused
        else { return false }

        let element = focused as! AXUIElement
        var selectedTextSettable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextSettable
        ) == .success,
        selectedTextSettable.boolValue,
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            return true
        }

        var valueSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &valueSettable
        ) == .success,
        valueSettable.boolValue
        else { return false }

        return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
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

    static func installToApplicationsAndRelaunch() {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications/ClipXS.app")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            NSWorkspace.shared.openApplication(at: destination, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("install_failed_title", comment: "")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
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
