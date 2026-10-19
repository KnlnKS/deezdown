import DeezDownKit
import SwiftUI

struct HomeScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Fetched("home", refreshable: true) { try await $0.home() } content: { feed in
            ScreenScroll {
                greeting
                CardShelf("Last Streamed by You", items: feed.history) { MediaCard($0) }
                CardShelf("Your Playlists", items: feed.playlists) { MediaCard($0) }
                CardShelf("Artists You Follow", items: feed.artists) { MediaCard($0) }
                CardShelf("Most Streamed Albums", items: feed.topAlbums) { MediaCard($0) }
                CardShelf("Popular Playlists", items: feed.topPlaylists) { MediaCard($0, subtitle: $0.owner) }
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
