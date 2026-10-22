import AppKit
import Carbon
import Foundation

final class HotkeyManager {
    static let shared = HotkeyManager()

    private enum HotkeyID: UInt32 {
        case panel = 1
        case queuePaste = 2
    }

    private var panelHotKeyRef: EventHotKeyRef?
    private var queueHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onHotkey: (() -> Void)?
    private var onQueuePaste: (() -> Void)?

    private init() {}

    func register(onHotkey: @escaping () -> Void, onQueuePaste: (() -> Void)? = nil) {
        self.onHotkey = onHotkey
        self.onQueuePaste = onQueuePaste
        installEventHandlerIfNeeded()
        registerCurrentHotkeys()
    }

    /// Re-registers with the current settings. Returns false (and restores the
    /// previous combo) when the new one is rejected, e.g. taken by the system.
    @discardableResult
    func applyHotkey(keyCode: UInt32, modifiers: UInt32, previousKeyCode: UInt32, previousModifiers: UInt32) -> Bool {
        unregisterHotkeys()
        if registerHotkey(keyCode: keyCode, modifiers: modifiers, id: .panel) {
            registerQueueHotkey(keyCode: keyCode, panelModifiers: modifiers)
            return true
        }
        _ = registerHotkey(keyCode: previousKeyCode, modifiers: previousModifiers, id: .panel)
        registerQueueHotkey(keyCode: previousKeyCode, panelModifiers: previousModifiers)
        return false
    }

    /// Temporarily releases the hotkeys so a recorder UI can capture the same combo.
    func suspend() {
        unregisterHotkeys()
    }

    func resume() {
        guard panelHotKeyRef == nil else { return }
        registerCurrentHotkeys()
    }

    func unregister() {
        unregisterHotkeys()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func registerCurrentHotkeys() {
        let keyCode = SettingsAccess.hotkeyKeyCode
        let modifiers = SettingsAccess.hotkeyModifiers
        _ = registerHotkey(keyCode: keyCode, modifiers: modifiers, id: .panel)
        registerQueueHotkey(keyCode: keyCode, panelModifiers: modifiers)
    }

    /// The queue-paste hotkey is the panel hotkey plus Shift. When the panel
    /// hotkey itself already contains Shift the combos collide, so the queue
    /// hotkey stays unregistered (and is reported in the log).
    private func registerQueueHotkey(keyCode: UInt32, panelModifiers: UInt32) {
        let queueModifiers = panelModifiers | UInt32(shiftKey)
        guard queueModifiers != panelModifiers else {
            NSLog("ClipXS: panel hotkey already uses Shift; queue-paste hotkey unavailable")
            return
        }
        _ = registerHotkey(keyCode: keyCode, modifiers: queueModifiers, id: .queuePaste)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                switch hotKeyID.id {
                case HotkeyID.panel.rawValue:
                    DispatchQueue.main.async { manager.onHotkey?() }
                case HotkeyID.queuePaste.rawValue:
                    DispatchQueue.main.async { manager.onQueuePaste?() }
                default:
                    break
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func registerHotkey(keyCode: UInt32, modifiers: UInt32, id: HotkeyID) -> Bool {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4350_5853), id: id.rawValue) // 'CPXS'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status != noErr {
            NSLog("ClipXS: RegisterEventHotKey (id \(id.rawValue)) failed with status \(status)")
            ref = nil
        }
        switch id {
        case .panel: panelHotKeyRef = ref
        case .queuePaste: queueHotKeyRef = ref
        }
        return status == noErr
    }

    private func unregisterHotkeys() {
        if let panelHotKeyRef {
            UnregisterEventHotKey(panelHotKeyRef)
            self.panelHotKeyRef = nil
        }
        if let queueHotKeyRef {
            UnregisterEventHotKey(queueHotKeyRef)
            self.queueHotKeyRef = nil
        }
    }
}
