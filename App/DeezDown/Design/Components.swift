import DeezDownKit
import SwiftUI

struct DownloadMenu<Label: View>: View {
    @Environment(AppModel.self) private var model
    var link: DeezerLink
    @ViewBuilder var label: () -> Label

    var body: some View {
        Menu {
            Button("Download") { Task { await model.enqueue(link) } }
            Divider()
            ForEach(TrackFormat.selectable, id: \.self) { format in
                Button("Download \(format.displayName)") {
                    Task { await model.enqueue(link, format: format) }
                }
                .disabled(model.user.map { !$0.canStream(format) } ?? true)
            }
            Divider()
            if let url = link.webURL {
                Button("Copy Deezer Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        } label: {
            label()
        } primaryAction: {
            Task { await model.enqueue(link) }
        }
    }
}

struct DownloadButton: View {
    var link: DeezerLink
    var title = "Download"

    var body: some View {
        DownloadMenu(link: link) {
            Label(title, systemImage: "arrow.down.circle.fill")
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .fixedSize()
    }
}

struct DownloadIconButton: View {
    var link: DeezerLink

    var body: some View {
        DownloadMenu(link: link) {
            Image(systemName: "arrow.down.circle")
                .font(.body)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Download")
    }
}

struct DownloadContextMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    var link: DeezerLink

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Download") { Task { await model.enqueue(link) } }
            Menu("Download As") {
                ForEach(TrackFormat.selectable, id: \.self) { format in
                    Button(format.displayName) { Task { await model.enqueue(link, format: format) } }
                        .disabled(model.user.map { !$0.canStream(format) } ?? true)
                }
            }
            Divider()
            if let url = link.webURL {
                Button("Copy Deezer Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                Button("Open in Deezer") { NSWorkspace.shared.open(url) }
            }
        }
    }
}

extension View {
    func downloadContextMenu(_ link: DeezerLink) -> some View {
        modifier(DownloadContextMenu(link: link))
    }
}

struct ExplicitBadge: View {
    var body: some View {
        Text("E")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.background)
            .frame(width: 13, height: 13)
            .background(Color.secondary, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .accessibilityLabel("Explicit")
    }
}

struct SectionHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .tracking(-0.2)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
    }
}

struct MediaCard: View {
    var picture: Artwork
    var title: String
    var subtitle: String
    var link: DeezerLink
    var circular = false
    var side: CGFloat = 156

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkView(picture: picture, side: side, corner: circular ? side / 2 : Metrics.cardCorner)
                DownloadIconButton(link: link)
                    .font(.title2)
                    .padding(8)
                    .opacity(hovering ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.85)
                    .shadow(radius: 6, y: 2)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: side, alignment: .leading)
            .multilineTextAlignment(.leading)
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .downloadContextMenu(link)
    }
}

struct ToastView: View {
    var toast: Toast?

    var body: some View {
        if let toast {
            Label(toast.message, systemImage: symbol(toast.kind))
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                .foregroundStyle(tint(toast.kind))
                .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(Motion.momentum, value: toast.id)
        }
    }

    private func symbol(_ kind: Toast.Kind) -> String {
        switch kind {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    private func tint(_ kind: Toast.Kind) -> Color {
        switch kind {
        case .info: .primary
        case .success: .success
        case .failure: .failure
        }
    }
}

struct LoadingState: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 80)
    }
}

extension Int {
    var formattedDuration: String {
        let minutes = self / 60
        let seconds = self % 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
