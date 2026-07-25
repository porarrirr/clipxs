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
        plainTextOnly: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        let target = resolveTargetApp(preferred: targetApp)

        guard let target, !target.isTerminated else {
            showNoTargetAlert()
            completion?(false)
            return
        }

        performPaste(entry: entry, into: target, plainTextOnly: plainTextOnly, completion: completion)
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
        plainTextOnly: Bool,
        completion: ((Bool) -> Void)?
    ) {
        let trusted = isAccessibilityTrusted(prompt: false)
        // Per-app rule: apps on the plain-paste list always receive plain text
        // (terminals, editors where rich formatting is unwanted).
        let forcePlain = entry.type == .text
            && SettingsAccess.plainPasteBundleIds.contains(target.bundleIdentifier ?? "")
        ClipboardMonitor.shared.suppressNextCapture()
        guard PasteboardRestore.restore(entry, plainTextOnly: plainTextOnly || forcePlain) else {
            showPasteFailedAlert()
            completion?(false)
            return
        }

        target.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

        // The frontmost poll already absorbs activation latency, so no fixed
        // lead-in delay is needed; keep a short settle before sending Cmd+V.
        waitUntilFrontmost(target, attempts: 15) { isFrontmost in
            guard isFrontmost else {
                showManualPasteNotification()
                completion?(true)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if trusted, postCommandV() {
                    completion?(true)
                } else {
                    showManualPasteNotification()
                    showPasteFailedAlert()
                    completion?(false)
                }
            }
        }
    }

    private static func waitUntilFrontmost(
        _ target: NSRunningApplication,
        attempts: Int,
        completion: @escaping (Bool) -> Void
    ) {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target.bundleIdentifier {
            completion(true)
            return
        }
        guard attempts > 0 else {
            completion(false)
            return
        }
        target.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            waitUntilFrontmost(target, attempts: attempts - 1, completion: completion)
        }
    }

    private static func postCommandV() -> Bool {
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
