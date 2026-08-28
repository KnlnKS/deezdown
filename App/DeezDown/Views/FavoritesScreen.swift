import DeezDownKit
import SwiftUI

struct FavoritesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<SearchResults> = .loading
    @State private var tab: Tab = .playlists

    enum Tab: String, CaseIterable, Identifiable {
        case playlists, albums, artists, tracks
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        AsyncContent(state: state, retry: { Task { await load() } }) { results in
            Group {
                switch tab {
                case .playlists where results.playlists.isEmpty,
                    .albums where results.albums.isEmpty,
                    .artists where results.artists.isEmpty,
                    .tracks where results.tracks.isEmpty:
                    ContentUnavailableView {
                        Label("No Favorite \(tab.title)", systemImage: "heart")
                    } description: {
                        Text("\(tab.title.capitalized) you favorite on Deezer show up here.")
                    }
                case .tracks:
                    List {
                        ForEach(Array(results.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, index: index + 1, showsArtwork: true, showsAlbum: true)
                        }
                    }
                    .listStyle(.inset)
                default:
                    ScreenScroll { grid(results) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem {
                    Button {
                        Task {
                            if let link = await model.library.lovedTracksLink() {
                                await model.enqueue(link)
                            } else {
                                model.show(Toast(message: "No loved tracks playlist", kind: .failure))
                            }
                        }
                    } label: {
                        Label("Download Loved Tracks", systemImage: "arrow.down.heart")
                    }
                    .help("Queue your loved tracks playlist")
                }
            }
        }
        .navigationTitle("Favorites")
        .task { await load() }
    }

    @ViewBuilder
    private func grid(_ results: SearchResults) -> some View {
        switch tab {
        case .albums:
            CardGrid(items: results.albums) { album in
                NavigationLink(value: Route.album(album.id)) {
                    MediaCard(picture: album.cover, title: album.title, subtitle: album.artist, link: album.link)
                }
                .buttonStyle(.plain)
            }
        case .artists:
            CardGrid(items: results.artists) { artist in
                NavigationLink(value: Route.artist(artist.id)) {
                    MediaCard(
                        picture: artist.picture, title: artist.name,
                        subtitle: "\(artist.fans.formatted()) fans", link: artist.link, circular: true
                    )
                }
                .buttonStyle(.plain)
            }
        default:
            CardGrid(items: results.playlists) { playlist in
                NavigationLink(value: Route.playlist(playlist.id)) {
                    MediaCard(
                        picture: playlist.picture, title: playlist.title,
                        subtitle: "\(playlist.trackCount) tracks", link: playlist.link
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await model.library.favorites())
        } catch {
            state = .failed(model.message(for: error))
        }
    }
}
