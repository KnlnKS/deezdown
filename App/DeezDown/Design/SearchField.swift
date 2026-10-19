import SwiftUI

/// Deezer's search bar: a filled, borderless field at the leading edge of the top bar.
struct SearchField: View {
    @Binding var text: String
    /// A new value asks the field to take focus.
    var focusRequest: UUID?
    var onSubmit: () -> Void

    @State private var focused = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            ToolbarTextField(text: $text, isFocused: $focused, focusRequest: focusRequest, onSubmit: onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 380, height: 34)
        .background(Color.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.brand, lineWidth: 2)
                .opacity(focused ? 1 : 0)
        }
        .animation(Motion.quick, value: focused)
    }
}

/// SwiftUI's focus state never reaches a text field in the toolbar, so this one is AppKit's:
/// it reports its own focus and takes focus when asked.
private struct ToolbarTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var focusRequest: UUID?
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.placeholderString = "Artists, albums, tracks, or a Deezer link"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.onFocus = { [coordinator = context.coordinator] in coordinator.parent.isFocused = true }
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if focusRequest != context.coordinator.handled {
            context.coordinator.handled = focusRequest
            field.window?.makeFirstResponder(field)
        }
    }

    final class Field: NSTextField {
        var onFocus: () -> Void = {}

        override func becomeFirstResponder() -> Bool {
            guard super.becomeFirstResponder() else { return false }
            onFocus()
            return true
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ToolbarTextField
        var handled: UUID?

        init(_ parent: ToolbarTextField) {
            self.parent = parent
            handled = parent.focusRequest
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.text = ""
            default: return false
            }
            return true
        }
    }
}
