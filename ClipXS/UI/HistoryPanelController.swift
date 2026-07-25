import AppKit
import SwiftUI

/// Borderless panels refuse key status by default; the panel must become key so
/// keyboard navigation reaches ClipXS instead of leaking into the app behind it.
private final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class HistoryPanelController: NSWindowController {
    static let shared = HistoryPanelController()
    private static let panelMargin: CGFloat = 16

    private let viewModel = HistoryViewModel()
    private var frontmostAppBeforePanel: NSRunningApplication?
    private var frontmostBundleIdBeforePanel: String?
    private var localKeyMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    private init() {
        let panel = HistoryPanel(
            contentRect: NSRect(origin: .zero, size: HistoryView.panelSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false

        super.init(window: panel)

        let host = NSHostingView(rootView: HistoryView(viewModel: viewModel))
        panel.contentView = host

        viewModel.onPaste = { [weak self] entry, plainTextOnly in
            let targetApp = self?.resolvedTargetApp()
            self?.hide()
            PasteService.paste(entry: entry, targetApp: targetApp, plainTextOnly: plainTextOnly)
            self?.clearTargetApp()
        }
        viewModel.onDismiss = { [weak self] in
            self?.hide()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        guard let window else { return }
        rememberFrontmostApp()
        viewModel.reload()
        positionNearCursor(window: window)
        window.makeKeyAndOrderFront(nil)
        installEventMonitors()
        focusSearchField()
    }

    /// The search box is an NSTextField hosted by SwiftUI; find it in the
    /// AppKit hierarchy once layout has happened and give it keyboard focus.
    private func focusSearchField() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, self.isVisible,
                  let contentView = window.contentView,
                  let field = Self.findTextField(in: contentView)
            else { return }
            window.makeFirstResponder(field)
        }
    }

    private static func findTextField(in view: NSView) -> NSTextField? {
        for subview in view.subviews {
            if let field = subview as? NSTextField, field.isEditable {
                return field
            }
            if let nested = findTextField(in: subview) {
                return nested
            }
        }
        return nil
    }

    func hide() {
        window?.orderOut(nil)
        removeEventMonitors()
    }

    private func positionNearCursor(window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visibleFrame = screen.visibleFrame
        let panelSize = window.frame.size

        if let focusedFrame = focusedElementFrame(),
           focusedFrame.intersects(visibleFrame) {
            window.setFrameOrigin(originAvoiding(focusedFrame, panelSize: panelSize, visibleFrame: visibleFrame))
            return
        }

        var origin = CGPoint(
            x: mouse.x + Self.panelMargin,
            y: mouse.y + Self.panelMargin
        )
        if origin.x + panelSize.width > visibleFrame.maxX {
            origin.x = mouse.x - panelSize.width - Self.panelMargin
        }
        if origin.y + panelSize.height > visibleFrame.maxY {
            origin.y = mouse.y - panelSize.height - Self.panelMargin
        }
        window.setFrameOrigin(clamped(origin, panelSize: panelSize, visibleFrame: visibleFrame))
    }

    private func originAvoiding(_ avoidedFrame: CGRect, panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let candidates = [
            CGPoint(x: avoidedFrame.midX - panelSize.width / 2, y: avoidedFrame.maxY + Self.panelMargin),
            CGPoint(x: avoidedFrame.midX - panelSize.width / 2, y: avoidedFrame.minY - panelSize.height - Self.panelMargin),
            CGPoint(x: avoidedFrame.maxX + Self.panelMargin, y: avoidedFrame.midY - panelSize.height / 2),
            CGPoint(x: avoidedFrame.minX - panelSize.width - Self.panelMargin, y: avoidedFrame.midY - panelSize.height / 2)
        ]

        if let nonOverlapping = candidates
            .map({ clamped($0, panelSize: panelSize, visibleFrame: visibleFrame) })
            .first(where: { !CGRect(origin: $0, size: panelSize).intersects(avoidedFrame.insetBy(dx: -8, dy: -8)) }) {
            return nonOverlapping
        }

        return clamped(
            CGPoint(x: visibleFrame.maxX - panelSize.width - Self.panelMargin, y: visibleFrame.maxY - panelSize.height - Self.panelMargin),
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
    }

    private func clamped(_ origin: CGPoint, panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: max(visibleFrame.minX + 8, min(origin.x, visibleFrame.maxX - panelSize.width - 8)),
            y: max(visibleFrame.minY + 8, min(origin.y, visibleFrame.maxY - panelSize.height - 8))
        )
    }

    private func focusedElementFrame() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success,
        let focused,
        CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        let element = unsafeDowncast(focused, to: AXUIElement.self)
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size),
              size.width > 0,
              size.height > 0
        else { return nil }

        let rawFrame = CGRect(origin: position, size: size)
        if NSScreen.screens.contains(where: { $0.frame.intersects(rawFrame) }) {
            return rawFrame
        }

        for screen in NSScreen.screens {
            let converted = CGRect(
                x: position.x,
                y: screen.frame.maxY - position.y - size.height,
                width: size.width,
                height: size.height
            )
            if screen.frame.intersects(converted) {
                return converted
            }
        }

        return nil
    }

    private func installEventMonitors() {
        removeEventMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKey(event) == true { return nil }
            return event
        }

        // Avoid treating the same click that opened the panel as an outside click.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.isVisible else { return }

            self.localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                self.handleClickOutside(event)
                return event
            }
            self.globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handleClickOutside(event)
            }
        }
    }

    private func removeEventMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func rememberFrontmostApp() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        frontmostAppBeforePanel = frontmost
        frontmostBundleIdBeforePanel = frontmost?.bundleIdentifier
    }

    private func resolvedTargetApp() -> NSRunningApplication? {
        if let bundleId = frontmostBundleIdBeforePanel,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first(where: { !$0.isTerminated }) {
            return app
        }
        if let frontmostAppBeforePanel, !frontmostAppBeforePanel.isTerminated {
            return frontmostAppBeforePanel
        }
        return nil
    }

    private func clearTargetApp() {
        frontmostAppBeforePanel = nil
        frontmostBundleIdBeforePanel = nil
    }

    private func handleClickOutside(_ event: NSEvent) {
        guard isVisible, let window else { return }
        let location = NSEvent.mouseLocation
        if !window.frame.contains(location) {
            hide()
        }
    }

    /// Single keyboard router for the panel. Consumes only navigation keys and
    /// ⌘-chords; everything else (letters, digits, Delete, IME input) falls
    /// through to the search field.
    private static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
    ]

    @discardableResult
    private func handleKey(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // While editing an entry, keys must reach the text editor; only the
        // editing chords are intercepted (⌘↩ save handled by SwiftUI's
        // keyboardShortcut on the save button, Esc cancels here).
        if viewModel.isEditing {
            if event.keyCode == 53 {
                viewModel.cancelEditing()
                return true
            }
            return false
        }

        switch event.keyCode {
        case 126: // up
            viewModel.selectPrevious()
            return true
        case 125: // down
            viewModel.selectNext()
            return true
        case 36 where flags.contains(.command): // cmd+return — add to paste queue
            viewModel.enqueueSelection()
            return true
        case 36: // return — plain pastes; shift+return pastes as plain text
            viewModel.pasteSelected(plainTextOnly: flags.contains(.shift))
            return true
        case 53: // escape — clears search → multi-selection → closes
            if !viewModel.searchText.isEmpty {
                viewModel.searchText = ""
            } else if !viewModel.multiSelectedIds.isEmpty {
                viewModel.clearMultiSelection()
            } else {
                hide()
            }
            return true
        case 51 where flags.contains(.command): // cmd+delete
            viewModel.deleteSelected()
            return true
        case 35 where flags.contains(.command): // cmd+P — toggle pin
            viewModel.togglePinSelected()
            return true
        case 14 where flags.contains(.command): // cmd+E — edit selected text entry
            viewModel.beginEditingSelected()
            return true
        default:
            if flags.contains(.command), let digit = Self.digitKeyCodes[event.keyCode] {
                viewModel.paste(at: digit - 1)
                return true
            }
            return false
        }
    }
}
