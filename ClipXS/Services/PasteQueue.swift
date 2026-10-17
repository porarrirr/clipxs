import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// Pastebot-style paste queue: entries added from the panel are pasted in
/// order with Command-V, Control-V, or the dedicated queue hotkey.
@MainActor
final class PasteQueue: ObservableObject {
    static let shared = PasteQueue()

    @Published private(set) var entries: [ClipboardEntry] = []
    /// Serializes hotkey presses: a second press while a paste is in flight
    /// would race the frontmost-app activation dance in PasteService.
    private var isPasting = false

    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private let monitorsKeyboard: Bool
    private let paste: (ClipboardEntry, @escaping (Bool) -> Void) -> Void

    init(
        monitorsKeyboard: Bool = true,
        paste: @escaping (ClipboardEntry, @escaping (Bool) -> Void) -> Void = {
            PasteService.paste(entry: $0, completion: $1)
        }
    ) {
        self.monitorsKeyboard = monitorsKeyboard
        self.paste = paste
    }

    deinit {
        if let eventTap { CFMachPortInvalidate(eventTap) }
        if let eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes) }
    }

    /// Ignore our generated Command-V, otherwise it would consume another item.
    static func isPasteShortcut(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != PasteService.generatedPasteMarker,
              event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_V) else { return false }
        let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        return modifiers == .maskCommand || modifiers == .maskControl
    }

    private func startMonitoring() {
        guard monitorsKeyboard, eventTap == nil, !entries.isEmpty else { return }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventType.keyDown.rawValue,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let queue = Unmanaged<PasteQueue>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = queue.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                        return Unmanaged.passUnretained(event)
                    }
                    guard type == .keyDown, !queue.entries.isEmpty,
                          PasteQueue.isPasteShortcut(event),
                          NSApp?.keyWindow == nil,
                          NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier
                    else { return Unmanaged.passUnretained(event) }
                    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        // Accessibility calls must not block the event-tap callback.
                        DispatchQueue.main.async { queue.pasteNext() }
                    }
                    return nil
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("ClipXS: could not monitor queue paste shortcuts; check Accessibility permission")
            _ = PasteService.isAccessibilityTrusted(prompt: true)
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopMonitoring() {
        if let eventTap { CFMachPortInvalidate(eventTap) }
        if let eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes) }
        eventTap = nil
        eventSource = nil
    }

    func enqueue(_ newEntries: [ClipboardEntry]) {
        entries.append(contentsOf: newEntries)
        startMonitoring()
    }

    func clear() {
        entries = []
        stopMonitoring()
    }

    func pasteNext() {
        guard !isPasting, let next = entries.first else { return }
        isPasting = true
        paste(next) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                self.isPasting = false
                // Keep the entry on failure so nothing is silently dropped.
                if success, self.entries.first?.id == next.id {
                    self.entries.removeFirst()
                    if self.entries.isEmpty { self.stopMonitoring() }
                }
            }
        }
    }
}
