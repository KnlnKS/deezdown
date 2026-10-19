import DeezDownKit
import SwiftUI

struct DownloadsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var issuesFor: QueueItem?

    var body: some View {
        Group {
            if model.queue.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Queued", systemImage: "arrow.down.circle")
                } description: {
                    Text("Downloads you start will appear here.")
                } actions: {
                    Button("Add Link…") { model.send(.addLink) }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.queue) { item in
                            DownloadRow(item: item) { issuesFor = item }
                        }
                    }
                    .padding(Metrics.gutter)
                    .animation(Motion.standard, value: model.queue.map(\.id))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Downloads")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Button { model.revealDownloads() } label: {
                    Label("Open Downloads Folder", systemImage: "folder")
                }
                .help("Open the downloads folder")
            }
            ToolbarItem {
                Button { model.resumeAll() } label: {
                    Label("Resume All", systemImage: "play.circle")
                }
                .disabled(model.summary.paused == 0)
                .help("Resume every paused download")
            }
            ToolbarItem {
                Button { model.clearFinished() } label: {
                    Label("Clear Finished", systemImage: "checklist.checked")
                }
                .disabled(!model.summary.canClear)
                .help("Clear finished downloads")
            }
            ToolbarItem {
                Button { model.cancelAll() } label: {
                    Label("Cancel All", systemImage: "xmark.circle")
                }
                .disabled(model.summary.active == 0)
                .help("Cancel everything in the queue")
            }
        }
        .sheet(item: $issuesFor) { item in IssuesSheet(item: item) }
    }

    private var subtitle: String {
        let summary = model.summary
        if summary.paused > 0, summary.active == summary.paused { return "\(summary.paused) paused" }
        if summary.active > summary.paused { return "\(summary.active - summary.paused) in progress" }
        let tracks = summary.downloadedTracks
        guard tracks > 0 else { return "" }
        return "\(tracks) track\(tracks == 1 ? "" : "s") downloaded"
    }
}

private struct DownloadRow: View {
    @Environment(AppModel.self) private var model
    var item: QueueItem
    var showIssues: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(picture: item.cover, side: 54, corner: 8)
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
                    .tint(barTint)
                    .opacity(item.status == .queued ? 0.35 : 1)
                    .frame(width: 220)
                HStack(spacing: 6) {
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                    if item.failedTracks > 0 {
                        Button(action: showIssues) {
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
        .background(Color.raised, in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
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
            if let url = item.link.webURL {
                Button("Copy Deezer Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
            Divider()
            Button("Remove", role: .destructive) { model.remove(item.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.title) by \(item.subtitle)")
        .accessibilityValue(statusText)
    }

    @ViewBuilder
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
        default: .secondary
        }
    }

    private var barTint: Color {
        switch item.status {
        case .failed: .failure
        case .withErrors: .warning
        case .completed: .success
        case .paused: .secondary
        default: .brand
        }
    }

    private var statusText: String {
        switch item.status {
        case .queued: "Waiting"
        case .resolving: "Looking up tracks…"
        case .downloading:
            item.totalTracks > 0
                ? "\(item.completedTracks + item.failedTracks) of \(item.totalTracks)"
                : "Downloading…"
        case .completed: "Done · \(item.totalTracks) track\(item.totalTracks == 1 ? "" : "s")"
        case .withErrors: "\(item.completedTracks) of \(item.totalTracks) downloaded"
        case .failed: "Failed"
        case .paused: item.totalTracks > 0
            ? "Paused · \(item.completedTracks + item.failedTracks) of \(item.totalTracks)" : "Paused"
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
                    Text("\(item.issues.count) track\(item.issues.count == 1 ? "" : "s") couldn't be downloaded")
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
