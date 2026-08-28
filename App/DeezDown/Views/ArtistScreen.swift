import DeezDownKit
import SwiftUI

struct ArtistScreen: View {
    @Environment(AppModel.self) private var model
    var id: String

    @State private var state: LoadState<ArtistDetail> = .loading
    @State private var tab: ArtistTab = .all

    var body: some View {
        AsyncContent(state: state, retry: { Task { await load() } }) { detail in
            ScreenScroll {
                header(detail)

                if !detail.topTracks.isEmpty {
                    SectionHeader("Top tracks") {
                        DownloadMenu(link: .artistTop(id)) {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .fixedSize()
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(detail.topTracks.prefix(10).enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, index: index + 1, showsAlbum: true)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 12)
                                .hoverHighlight(corner: 6)
                        }
                    }
                    .padding(.vertical, 6)
                    .background(Color.raised, in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06))
                    }
                }

                UnderlineTabs(selection: $tab, options: availableTabs(detail))
                    .padding(.top, 4)

                if let albums = detail.albums[tab] ?? detail.albums[.all], !albums.isEmpty {
                    CardGrid(items: albums) { album in
                        NavigationLink(value: Route.album(album.id)) {
                            MediaCard(
                                picture: album.cover, title: album.title,
                                subtitle: subtitle(for: album), link: album.link
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !detail.biography.isEmpty {
                    SectionHeader("About")
                    Text(detail.biography)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 720, alignment: .leading)
                }
            }
        }
        .navigationTitle(title)
        .task(id: id) { await load() }
    }

    private var title: String {
        if case .loaded(let detail) = state { return detail.summary.name }
        return "Artist"
    }

    private func subtitle(for album: AlbumSummary) -> String {
        [album.year, album.recordType.displayName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func availableTabs(_ detail: ArtistDetail) -> [(value: ArtistTab, title: String)] {
        ArtistTab.allCases
            .filter { detail.albums[$0]?.isEmpty == false }
            .map { ($0, $0.title) }
    }

    private func header(_ detail: ArtistDetail) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            CircularArtworkView(picture: detail.summary.picture, side: 190)
                .shadow(color: .black.opacity(0.28), radius: 22, y: 10)

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Artist")
                DisplayTitle(text: detail.summary.name)
                Text("\(detail.summary.fans.formatted()) fans • \(detail.albums[.all]?.count ?? 0) releases")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                DownloadButton(link: .artist(id, tab: tab), title: "Download \(tab.title)")
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await model.library.artist(id: id))
        } catch {
            state = .failed(model.message(for: error))
        }
    }
}
