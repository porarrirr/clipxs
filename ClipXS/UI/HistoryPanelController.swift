import AppKit
import SwiftUI

final class HistoryPanelController: NSWindowController {
    static let shared = HistoryPanelController()
    private static let panelMargin: CGFloat = 16

    private let viewModel = HistoryViewModel()
    private var frontmostAppBeforePanel: NSRunningApplication?
    private var frontmostBundleIdBeforePanel: String?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
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

        viewModel.onPaste = { [weak self] entry in
            let targetApp = self?.resolvedTargetApp()
            self?.hide()
            PasteService.paste(entry: entry, targetApp: targetApp)
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
        window.orderFrontRegardless()
        installEventMonitors()
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
        let focused
        else { return nil }

        let element = focused as! AXUIElement
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
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
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKey(event)
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
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
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

    @discardableResult
    private func handleKey(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        switch event.keyCode {
        case 126: // up
            viewModel.selectPrevious()
            return true
        case 125: // down
            viewModel.selectNext()
            return true
        case 36: // return
            viewModel.pasteSelected()
            return true
        case 53: // escape
            hide()
            return true
        default:
            return false
        }
    }
}
