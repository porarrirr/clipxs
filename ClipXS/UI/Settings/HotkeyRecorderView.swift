import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotkeyRecorderView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var showConflictAlert = false

    var body: some View {
        HStack {
            Button(action: toggleRecording) {
                Text(buttonTitle)
                    .frame(minWidth: 140)
            }
            if isRecording {
                Text(String(localized: "settings_hotkey_recording_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert(String(localized: "settings_hotkey_conflict_title"), isPresented: $showConflictAlert) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings_hotkey_conflict_message"))
        }
        .onDisappear { stopRecording(resumeHotkey: true) }
    }

    private var buttonTitle: String {
        if isRecording {
            return String(localized: "settings_hotkey_recording")
        }
        return HotkeyFormatter.displayString(
            keyCode: settings.hotkeyKeyCode,
            carbonModifiers: settings.hotkeyModifiers
        )
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording(resumeHotkey: true)
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        // Release the current hotkey so the same combo can be re-entered.
        HotkeyManager.shared.suspend()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRecordedKey(event)
            return nil
        }
    }

    private func stopRecording(resumeHotkey: Bool) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        isRecording = false
        if resumeHotkey {
            HotkeyManager.shared.resume()
        }
    }

    private func handleRecordedKey(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            stopRecording(resumeHotkey: true)
            return
        }

        let modifiers = HotkeyFormatter.carbonModifiers(from: event.modifierFlags)
        // Require a real chord: at least one of ⌘/⌥/⌃ (shift alone would
        // swallow ordinary typing system-wide).
        let chordMask = UInt32(cmdKey | optionKey | controlKey)
        guard modifiers & chordMask != 0 else { return }

        let keyCode = UInt32(event.keyCode)
        let previousKeyCode = settings.hotkeyKeyCode
        let previousModifiers = settings.hotkeyModifiers

        stopRecording(resumeHotkey: false)

        let applied = HotkeyManager.shared.applyHotkey(
            keyCode: keyCode,
            modifiers: modifiers,
            previousKeyCode: previousKeyCode,
            previousModifiers: previousModifiers
        )
        if applied {
            settings.hotkeyKeyCode = keyCode
            settings.hotkeyModifiers = modifiers
        } else {
            showConflictAlert = true
        }
    }
}
