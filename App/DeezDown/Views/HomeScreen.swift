import DeezDownKit
import SwiftUI

struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<HomeFeed> = .loading

    var body: some View {
        AsyncContent(state: state, retry: { Task { await load(force: true) } }) { feed in
            ScreenScroll {
                greeting

                if !feed.history.isEmpty {
                    SectionHeader("Last Streamed by You")
                    CardGrid(items: feed.history, rows: 2) { album in
                        NavigationLink(value: Route.album(album.id)) {
                            MediaCard(
                                picture: album.cover, title: album.title,
                                subtitle: album.artist, link: album.link
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !feed.playlists.isEmpty {
                    SectionHeader("Your Playlists")
                    CardGrid(items: feed.playlists, rows: 1) { playlist in
                        NavigationLink(value: Route.playlist(playlist.id)) {
                            MediaCard(
                                picture: playlist.picture, title: playlist.title,
                                subtitle: "\(playlist.trackCount) tracks", link: playlist.link
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !feed.artists.isEmpty {
                    SectionHeader("Artists You Follow")
                    CardGrid(items: feed.artists, rows: 1) { artist in
                        NavigationLink(value: Route.artist(artist.id)) {
                            MediaCard(
                                picture: artist.picture, title: artist.name,
                                subtitle: "\(artist.fans.formatted()) fans", link: artist.link,
                                circular: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !feed.topAlbums.isEmpty {
                    SectionHeader("Most Streamed Albums")
                    CardGrid(items: feed.topAlbums, rows: 2) { album in
                        NavigationLink(value: Route.album(album.id)) {
                            MediaCard(
                                picture: album.cover, title: album.title,
                                subtitle: album.artist, link: album.link
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !feed.topPlaylists.isEmpty {
                    SectionHeader("Popular Playlists")
                    CardGrid(items: feed.topPlaylists, rows: 1) { playlist in
                        NavigationLink(value: Route.playlist(playlist.id)) {
                            MediaCard(
                                picture: playlist.picture, title: playlist.title,
                                subtitle: playlist.owner, link: playlist.link
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem {
                Button { Task { await load(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Fetch the latest from Deezer")
            }
        }
        .task { await load() }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back\(model.user.map { ", \($0.name)" } ?? "")")
                .font(.system(size: 30, weight: .heavy))
                .fontWidth(.condensed)
                .tracking(-0.3)
            Text("Search for anything, or paste a Deezer link to download it.")
                .foregroundStyle(.secondary)
        }
    }

    private func load(force: Bool = false) async {
        if !force, let cached = model.cache.value("home", as: HomeFeed.self) {
            state = .loaded(cached)
            return
        }
        if case .loaded = state {} else { state = .loading }
        do {
            let fresh = try await model.library.home()
            model.cache.store(fresh, for: "home")
            state = .loaded(fresh)
        } catch {
            state = .failed(model.message(for: error))
        }
    }
}
