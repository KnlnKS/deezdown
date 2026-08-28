import DeezDownKit
import SwiftUI

struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<SearchResults> = .loading

    var body: some View {
        AsyncContent(state: state, retry: { Task { await load() } }) { results in
            ScreenScroll {
                greeting
                if !results.albums.isEmpty {
                    SectionHeader("Most Streamed Albums")
                    CardGrid(items: results.albums) { album in
                        NavigationLink(value: Route.album(album.id)) {
                            MediaCard(
                                picture: album.cover, title: album.title,
                                subtitle: album.artist, link: album.link
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !results.playlists.isEmpty {
                    SectionHeader("Popular Playlists")
                    CardGrid(items: results.playlists) { playlist in
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
        .task { await load() }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back\(model.user.map { ", \($0.name)" } ?? "")")
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)
            Text("Search for anything, or paste a Deezer link to download it.")
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await model.library.charts())
        } catch {
            state = .failed(model.message(for: error))
        }
    }
}
