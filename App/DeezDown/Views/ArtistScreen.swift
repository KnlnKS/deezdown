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
                    SectionHeader("Popular") {
                        DownloadMenu(link: .artistTop(id)) {
                            Label("Download Top Tracks", systemImage: "arrow.down.circle")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.bordered)
                        .fixedSize()
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(detail.topTracks.prefix(10).enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, index: index + 1, showsAlbum: true)
                                .padding(.vertical, 2)
                        }
                    }
                }

                if let albums = detail.albums[tab] ?? detail.albums[.all], !albums.isEmpty {
                    SectionHeader("Discography") { tabPicker(detail) }
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

    private func tabPicker(_ detail: ArtistDetail) -> some View {
        Picker("Show", selection: $tab) {
            ForEach(ArtistTab.allCases, id: \.self) { option in
                if detail.albums[option]?.isEmpty == false {
                    Text(option.title).tag(option)
                }
            }
        }
        .fixedSize()
    }

    private func header(_ detail: ArtistDetail) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            CircularArtworkView(picture: detail.summary.picture, side: 152)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("ARTIST")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.brand)
                Text(detail.summary.name)
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.6)
                Text("\(detail.summary.fans.formatted()) fans · \(detail.albums[.all]?.count ?? 0) releases")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                DownloadButton(link: .artist(id, tab: tab), title: "Download \(tab.title)")
                    .padding(.top, 6)
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
