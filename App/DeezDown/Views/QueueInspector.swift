import DeezDownKit
import SwiftUI

struct QueueInspector: View {
    @Environment(AppModel.self) private var model
    @State private var issuesFor: QueueItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.queue.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Queued", systemImage: "arrow.down.circle")
                } description: {
                    Text("Downloads you start will appear here.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.queue) { item in
                            QueueRow(item: item) { issuesFor = item }
                        }
                    }
                    .padding(10)
                    .animation(Motion.standard, value: model.queue.map(\.id))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $issuesFor) { item in IssuesSheet(item: item) }
    }

    /// Lives in the panel rather than the window toolbar so the controls disappear with it.
    private var header: some View {
        HStack(spacing: 6) {
            Text("Downloads")
                .font(.headline)
            if model.activeDownloads > 0 {
                Text("\(model.activeDownloads)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.brandSoft, in: Capsule())
                    .foregroundStyle(.brand)
            }
            Spacer(minLength: 0)
            Button { model.revealDownloads() } label: { Image(systemName: "folder") }
                .help("Open the downloads folder")
                .accessibilityLabel("Open the downloads folder")
            Button { model.clearFinished() } label: { Image(systemName: "checklist.checked") }
                .disabled(!model.queue.contains { $0.status == .completed })
                .help("Clear finished downloads")
                .accessibilityLabel("Clear finished downloads")
            Button { model.cancelAll() } label: { Image(systemName: "xmark.circle") }
                .disabled(model.activeDownloads == 0)
                .help("Cancel everything in the queue")
                .accessibilityLabel("Cancel everything in the queue")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

private struct QueueRow: View {
    @Environment(AppModel.self) private var model
    var item: QueueItem
    var showIssues: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(picture: item.cover, side: 46, corner: 7)
                Text(item.format.displayName)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.white)
                    .padding(3)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    action
                }
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)

                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
                    .tint(barTint)
                    .opacity(item.status == .queued ? 0.35 : 1)

                HStack(spacing: 6) {
                    Text(statusText).font(.caption2).foregroundStyle(.secondary)
                    if item.failedTracks > 0 {
                        Button(action: showIssues) {
                            Label("\(item.failedTracks)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.failure)
                        .help("Show what failed")
                    }
                }
            }
        }
        .padding(8)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.title) by \(item.subtitle)")
        .accessibilityValue(statusText)
    }

    @ViewBuilder
    private var action: some View {
        if item.canRetry, hovering {
            Button { model.retry(item.id) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Retry")
        } else if item.status.isFinished {
            Button { model.remove(item.id) } label: { Image(systemName: symbol) }
                .buttonStyle(.plain).foregroundStyle(tint).help("Remove from the queue")
        } else {
            Button { model.cancel(item.id) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Cancel")
        }
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
        case .canceled: "Canceled"
        }
    }
}

private struct IssuesSheet: View {
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
