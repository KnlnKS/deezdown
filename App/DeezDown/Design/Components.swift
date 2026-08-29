import DeezDownKit
import SwiftUI

struct DownloadButton: View {
    @Environment(AppModel.self) private var model
    var link: DeezerLink
    var title = "Download"

    var body: some View {
        Button {
            Task { await model.enqueue(link) }
        } label: {
            Label(title, systemImage: "arrow.down.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .fixedSize()
    }
}

struct DownloadIconButton: View {
    @Environment(AppModel.self) private var model
    var link: DeezerLink

    var body: some View {
        Button {
            Task { await model.enqueue(link) }
        } label: {
            Image(systemName: "arrow.down.circle")
                .font(.body)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Download")
        .accessibilityLabel("Download")
    }
}

/// Sits on the artwork, so it needs its own ground to stay legible over any cover.
struct CardDownloadButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var link: DeezerLink
    var isVisible: Bool

    var body: some View {
        Button {
            Task { await model.enqueue(link) }
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.brand, in: Circle())
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .pressable(scale: 0.9)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible || reduceMotion ? 1 : 0.6)
        .help("Download")
        .accessibilityLabel("Download")
    }
}

struct DownloadContextMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator: Navigator?
    @Environment(\.currentRoute) private var currentRoute
    var link: DeezerLink
    var track: TrackSummary?

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Download") { Task { await model.enqueue(link) } }
            if let track {
                Divider()
                destination("Go to Artist", .artist(track.artistID))
                destination("Go to Album", .album(track.albumID))
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

    /// The page the row is already sitting on isn't offered as somewhere to go.
    @ViewBuilder
    private func destination(_ title: String, _ route: Route) -> some View {
        if route != currentRoute, let navigator {
            Button(title) { navigator.open(route) }
        }
    }
}

extension View {
    func downloadContextMenu(_ link: DeezerLink, track: TrackSummary? = nil) -> some View {
        modifier(DownloadContextMenu(link: link, track: track))
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

/// A card is a link to whatever it shows, so it carries its own navigation rather than
/// making every grid wrap it.
struct MediaCard: View {
    var picture: Artwork
    var title: String
    var subtitle: String
    var link: DeezerLink
    var circular = false

    @State private var hovering = false

    @ViewBuilder
    var body: some View {
        if let route = Route(link: link) {
            NavigationLink(value: route) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                FillingArtworkView(picture: picture, isCircular: circular)
                CardDownloadButton(link: link, isVisible: hovering)
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(Motion.momentum, value: hovering)
        .downloadContextMenu(link)
    }
}

extension MediaCard {
    init(_ album: AlbumSummary, subtitle: String? = nil) {
        self.init(
            picture: album.cover, title: album.title,
            subtitle: subtitle ?? album.artist, link: album.link
        )
    }

    init(_ artist: ArtistSummary) {
        self.init(
            picture: artist.picture, title: artist.name,
            subtitle: "\(artist.fans.formatted()) fans", link: artist.link, circular: true
        )
    }

    init(_ playlist: PlaylistSummary, title: String? = nil, subtitle: String? = nil) {
        self.init(
            picture: playlist.picture, title: title ?? playlist.title,
            subtitle: subtitle ?? "\(playlist.trackCount) tracks", link: playlist.link
        )
    }
}

/// Every browsing screen offers the same way to go and ask Deezer again.
struct RefreshButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .help("Fetch the latest from Deezer")
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

/// Deezer puts a pill next to each section heading; this is the Mac-weight version.
struct PillButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .buttonBorderShape(.capsule)
    }
}

/// Deezer sets release and artist names in a heavy condensed grotesque; SF's condensed
/// width is the native equivalent and keeps long titles on one line.
struct DisplayTitle: View {
    var text: String
    var size: CGFloat = 40

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy))
            .fontWidth(.condensed)
            .tracking(-0.5)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct Eyebrow: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1)
            .foregroundStyle(.brand)
    }
}

/// Underlined tabs, the way Deezer separates an artist's discography sections.
struct UnderlineTabs<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]

    @Namespace private var underline

    var body: some View {
        HStack(spacing: 22) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.callout.weight(selection == option.value ? .semibold : .regular))
                        .foregroundStyle(selection == option.value ? .primary : .secondary)
                        .padding(.bottom, 8)
                        // Overlaying keeps the rule exactly as wide as its label.
                        .overlay(alignment: .bottom) {
                            if selection == option.value {
                                Capsule()
                                    .fill(Color.brand)
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .animation(Motion.standard, value: selection)
    }
}
