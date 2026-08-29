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
                    CardGrid(items: feed.history, rows: 2) { MediaCard($0) }
                }

                if !feed.playlists.isEmpty {
                    SectionHeader("Your Playlists")
                    CardGrid(items: feed.playlists, rows: 1) { MediaCard($0) }
                }

                if !feed.artists.isEmpty {
                    SectionHeader("Artists You Follow")
                    CardGrid(items: feed.artists, rows: 1) { MediaCard($0) }
                }

                if !feed.topAlbums.isEmpty {
                    SectionHeader("Most Streamed Albums")
                    CardGrid(items: feed.topAlbums, rows: 2) { MediaCard($0) }
                }

                if !feed.topPlaylists.isEmpty {
                    SectionHeader("Popular Playlists")
                    CardGrid(items: feed.topPlaylists, rows: 1) { MediaCard($0, subtitle: $0.owner) }
                }
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem {
                RefreshButton { Task { await load(force: true) } }
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
        await model.load("home", force: force, into: { state = $0 }) { try await model.library.home() }
    }
}
