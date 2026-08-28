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
                Button("Find") { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                    .keyboardShortcut("f", modifiers: .command)
            }
            SidebarCommands()
            InspectorCommands()
            DownloadCommands(model: model)
            CommandGroup(replacing: .newItem) {}
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
            Button("Add Link…") { NotificationCenter.default.post(name: .showAddLink, object: nil) }
                .keyboardShortcut("l", modifiers: .command)

            // Plain paste belongs to text fields, so queueing a copied link gets its own shortcut.
            Button("Paste and Queue") {
                guard let text = NSPasteboard.general.string(forType: .string) else { return }
                Task { await model.enqueue(pasted: text) }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

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
            .disabled(!model.queue.contains(where: \.canRetry))

            Button("Clear Finished") { model.clearFinished() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(!model.queue.contains { $0.status == .completed })

            Button("Cancel All") { model.cancelAll() }
                .disabled(model.activeDownloads == 0)

            Divider()

            Button("Open Downloads Folder") { model.revealDownloads() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }

    private func qualityBinding(_ format: TrackFormat) -> Binding<Bool> {
        Binding(
            get: { model.settings.maxBitrate == format },
            set: { isOn in
                guard isOn else { return }
                model.settings.maxBitrate = format
                model.saveSettings()
            }
        )
    }
}

extension Notification.Name {
    static let showAddLink = Notification.Name("DeezDown.showAddLink")
    static let focusSearch = Notification.Name("DeezDown.focusSearch")
}
