import DeezDownKit
import SwiftUI

struct FavoritesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var tab = SearchKind.playlist

    var body: some View {
        TabbedPage(selection: $tab, options: [SearchKind.playlist, .album, .artist, .track].map { ($0, $0.title) }) {
            content
        }
        .toolbar {
            ToolbarItem {
                if tab == .track, let lovedTracks = model.user?.lovedTracks {
                    Button("Download All", systemImage: "arrow.down.circle") {
                        Task { await model.enqueue([lovedTracks]) }
                    }
                    .help("Download every favorite track")
                }
            }
        }
    }

    private var content: some View {
        Fetched("favorites", refreshable: true) { try await $0.favorites() } content: { results in
            switch tab {
            case .playlist where results.playlists.isEmpty,
                .album where results.albums.isEmpty,
                .artist where results.artists.isEmpty,
                .track where results.tracks.isEmpty:
                ContentUnavailableView {
                    Label("No Favorite \(tab.title)", systemImage: "heart")
                } description: {
                    Text("\(tab.title) you favorite on Deezer show up here.")
                }
            case .track:
                List {
                    ForEach(results.tracks) { track in
                        TrackRow(track: track, showsArtwork: true, showsAlbum: true)
                            .trackRowInsets()
                    }
                }
                .trackListStyle()
            case .album: ScreenScroll { CardGrid(items: results.albums) { MediaCard($0) } }
            case .artist: ScreenScroll { CardGrid(items: results.artists) { MediaCard($0) } }
            case .playlist: ScreenScroll { CardGrid(items: results.playlists) { MediaCard($0) } }
            }
        }
    }
}
