import AppKit
import SwiftUI

/// NSTextField-backed search box. SwiftUI's TextField + @FocusState is
/// unreliable for programmatic focus inside a borderless nonactivating panel,
/// while a plain NSTextField in a key panel receives typing fine (the
/// Spotlight pattern). HistoryPanelController focuses it via makeFirstResponder.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        if let cell = field.cell as? NSTextFieldCell {
            cell.sendsActionOnEndEditing = false
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField

        init(_ parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}
