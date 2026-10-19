import DeezDownKit
import SwiftUI

@main
struct DeezDownApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .task { await model.restore() }
        }
        .defaultSize(width: 1160, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Find") { model.send(.findInSearch) }
                    .keyboardShortcut("f", modifiers: .command)
            }
            SidebarCommands()
            DownloadCommands(model: model)
            // Replacing New Item with an empty group makes SwiftUI treat the File menu as
            // trivial and trap while pruning it, so it carries a real command instead.
            CommandGroup(replacing: .newItem) {
                Button("Add Link…") { model.send(.addLink) }
                    .keyboardShortcut("l", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Link("Deezer", destination: URL(string: "https://www.deezer.com")!)
            }
        }

        Settings {
            SettingsScreen()
                .environment(model)
        }
    }
}

struct DownloadCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandMenu("Downloads") {
            // Plain paste belongs to text fields, so queueing a copied link gets its own shortcut.
            Button("Paste and Queue") {
                guard let text = NSPasteboard.general.string(forType: .string) else { return }
                Task { await model.enqueue(pasted: text) }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("Show Downloads") { model.send(.showDownloads) }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Menu("Download Quality") {
                ForEach(TrackFormat.selectable, id: \.self) { format in
                    Toggle(format.displayName, isOn: qualityBinding(format))
                        .disabled(model.user.map { !$0.canStream(format) } ?? true)
                }
            }

            Divider()

            Button("Retry Failed") {
                for item in model.queue where item.canRetry { model.retry(item.id) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!model.summary.canRetry)

            Button("Clear Finished") { model.clearFinished() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(!model.summary.canClear)

            Button("Cancel All") { model.cancelAll() }
                .disabled(model.summary.active == 0)

            Divider()

            Button("Open Downloads Folder") { model.revealDownloads() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }

    private func qualityBinding(_ format: TrackFormat) -> Binding<Bool> {
        Binding(
            get: { model.settings.maxBitrate == format },
            set: { isOn in
                if isOn { model.settings.maxBitrate = format }
            }
        )
    }
}
