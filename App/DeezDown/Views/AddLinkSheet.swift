import DeezDownKit
import SwiftUI

struct AddLinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var format: TrackFormat?
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add to Queue").font(.headline)
                Text("Paste one or more Deezer links, separated by spaces or new lines.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 96)
                .background(Color.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
                .focused($focused)

            HStack {
                Picker("Quality", selection: $format) {
                    Text("Default (\(model.settings.maxBitrate.displayName))").tag(TrackFormat?.none)
                    Divider()
                    ForEach(TrackFormat.selectable, id: \.self) { option in
                        Text(option.displayName).tag(TrackFormat?.some(option))
                    }
                }
                .fixedSize()

                Spacer()

                Text("⌘↩").font(.caption).foregroundStyle(.tertiary)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                // The text editor swallows plain Return, so Command-Return is the way in.
                Button("Add") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
            }
        }
        .padding(Metrics.gutter)
        .frame(width: 520)
        .onAppear {
            focused = true
            if let pasted = NSPasteboard.general.string(forType: .string),
                (try? LinkParser.parse(pasted)) != nil
            {
                text = pasted
            }
        }
    }

    private func submit() {
        working = true
        let input = text
        let chosen = format
        Task {
            for candidate in LinkParser.split(input) {
                do {
                    await model.enqueue(try await LinkParser.resolve(candidate), format: chosen)
                } catch {
                    model.show(Toast(message: model.message(for: error), kind: .failure))
                }
            }
            dismiss()
        }
    }
}
