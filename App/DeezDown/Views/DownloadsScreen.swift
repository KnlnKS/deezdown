import DeezDownKit
import SwiftUI

struct DownloadsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.summary.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Queued", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download anything you browse, or paste a Deezer link into the search bar.")
                }
                .blendsWithToolbar()
            } else {
                DownloadList()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem {
                Button("Open Downloads Folder", systemImage: "folder") { model.revealDownloads() }
                    .help("Open the downloads folder")
            }
            ToolbarItem {
                Button("Clear Finished", systemImage: "checklist.checked") { model.clearFinished() }
                    .disabled(!model.summary.canClear)
                    .help("Clear finished downloads")
            }
            ToolbarItem {
                if model.summary.canPause {
                    Button("Pause All", systemImage: "pause.circle") { model.pause() }
                        .help("Pause every download")
                } else {
                    Button("Resume All", systemImage: "play.circle") { model.resume() }
                        .disabled(!model.summary.canResume)
                        .help("Resume every paused download")
                }
            }
            ToolbarItem {
                Button("Cancel All", systemImage: "xmark.circle") { model.cancel() }
                    .disabled(model.summary.active == 0)
                    .help("Cancel everything in the queue")
            }
        }
    }
}

/// Progress changes the queue many times a second, so only the list reads it; the page and its
/// toolbar follow the summary.
private struct DownloadList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(model.queue) { DownloadRow(item: $0) }
            }
            .padding(Metrics.gutter)
            .animation(Motion.standard, value: model.queue.count)
        }
    }
}

/// Takes nothing but the item, so a progress tick redraws only the rows whose item changed.
private struct DownloadRow: View {
    @Environment(AppModel.self) private var model
    var item: QueueItem

    @State private var hovering = false
    @State private var showingIssues = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(picture: item.cover, side: 54)
                Text(item.format.displayName)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.white)
                    .padding(3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                Text(item.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .opacity(item.status == .queued ? 0.35 : 1)
                    .frame(width: 220)
                HStack(spacing: 6) {
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                    if item.failedTracks > 0 {
                        Button { showingIssues = true } label: {
                            Label("\(item.failedTracks)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.failure)
                        .help("Show what failed")
                    }
                }
            }

            actions
                .frame(width: 64, alignment: .trailing)
        }
        .padding(12)
        .raisedCard()
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu {
            if item.canPause { Button("Pause") { model.pause(item.id) } }
            if item.canResume { Button("Resume") { model.resume(item.id) } }
            if item.canRetry { Button("Retry") { model.retry(item.id) } }
            if let destination = item.destination {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destination.path(percentEncoded: false))
                }
            }
            if let url = item.link.webURL { CopyLinkButton(url: url) }
            Divider()
            Button("Remove", role: .destructive) { model.remove(item.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.title) by \(item.subtitle)")
        .accessibilityValue(statusText)
        .sheet(isPresented: $showingIssues) { IssuesSheet(item: item) }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if item.canPause {
                rowButton("Pause", symbol: "pause.fill") { model.pause(item.id) }
            } else if item.canResume {
                rowButton("Resume", symbol: "play.fill", style: .brand) { model.resume(item.id) }
            } else if item.canRetry {
                rowButton("Retry", symbol: "arrow.clockwise") { model.retry(item.id) }
            }

            // One slot: the outcome badge swaps to a remove button under the pointer,
            // so nothing shifts as the row is hovered.
            ZStack {
                if item.status.isFinished {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                        .opacity(hovering ? 0 : 1)
                        .accessibilityHidden(true)
                    rowButton("Remove", symbol: "xmark.circle.fill", help: "Remove from the list") {
                        model.remove(item.id)
                    }
                    .opacity(hovering ? 1 : 0)
                } else {
                    rowButton("Cancel", symbol: "xmark.circle.fill") { model.cancel(item.id) }
                }
            }
            .frame(width: 18)
        }
    }

    private func rowButton(
        _ verb: String, symbol: String, help: String? = nil, style: some ShapeStyle = HierarchicalShapeStyle.secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .foregroundStyle(style)
            .help(help ?? verb)
            .accessibilityLabel("\(verb) \(item.title)")
    }

    private var symbol: String {
        switch item.status {
        case .completed: "checkmark.circle.fill"
        case .withErrors: "exclamationmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        default: "minus.circle.fill"
        }
    }

    private var tint: Color {
        switch item.status {
        case .completed: .success
        case .withErrors: .warning
        case .failed: .failure
        case .paused, .canceled: .secondary
        case .queued, .resolving, .downloading: .brand
        }
    }

    private var statusText: String {
        let tally = item.totalTracks > 0 ? "\(item.completedTracks + item.failedTracks) of \(item.totalTracks)" : nil
        return switch item.status {
        case .queued: "Waiting"
        case .resolving: "Looking up tracks…"
        case .downloading: tally ?? "Downloading…"
        case .completed: "Done · \(item.totalTracks.tracksLabel)"
        case .withErrors: "\(item.completedTracks) of \(item.totalTracks) downloaded"
        case .failed: "Failed"
        case .paused: tally.map { "Paused · \($0)" } ?? "Paused"
        case .canceled: "Canceled"
        }
    }
}

struct IssuesSheet: View {
    @Environment(\.dismiss) private var dismiss
    var item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline)
                    Text("\(item.issues.count.tracksLabel) couldn't be downloaded")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Metrics.gutter)

            Divider()

            Table(item.issues) {
                TableColumn("Track") { Text($0.title) }
                TableColumn("Artist") { Text($0.artist).foregroundStyle(.secondary) }
                TableColumn("Reason") { Text($0.message).foregroundStyle(.secondary) }
            }
        }
        .frame(width: 660, height: 380)
    }
}
