import DeezDownKit
import SwiftUI

struct HomeScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Fetched("home", refreshable: true) { try await $0.home() } content: { feed in
            ScreenScroll {
                greeting

                if !feed.history.isEmpty {
                    CardShelf("Last Streamed by You", items: feed.history, rows: 2) { MediaCard($0) }
                }

                if !feed.playlists.isEmpty {
                    CardShelf("Your Playlists", items: feed.playlists) { MediaCard($0) }
                }

                if !feed.artists.isEmpty {
                    CardShelf("Artists You Follow", items: feed.artists) { MediaCard($0) }
                }

                if !feed.topAlbums.isEmpty {
                    CardShelf("Most Streamed Albums", items: feed.topAlbums, rows: 2) { MediaCard($0) }
                }

                if !feed.topPlaylists.isEmpty {
                    CardShelf("Popular Playlists", items: feed.topPlaylists) { MediaCard($0, subtitle: $0.owner) }
                }
            }
        }
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
}
