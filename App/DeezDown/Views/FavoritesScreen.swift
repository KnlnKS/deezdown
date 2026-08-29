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
        VStack(spacing: 0) {
            UnderlineTabs(selection: $tab, options: Tab.allCases.map { ($0, $0.title) })
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 16)
                .padding(.bottom, 8)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Favorites")
        .toolbar {
            ToolbarItem {
                RefreshButton { Task { await load(force: true) } }
            }
        }
        .task { await load() }
    }

    private var content: some View {
        AsyncContent(state: state, retry: { Task { await load(force: true) } }) { results in
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
                                .trackRowInsets()
                        }
                    }
                    .listStyle(.inset)
                default:
                    ScreenScroll { grid(results) }
                }
            }
        }
    }

    @ViewBuilder
    private func grid(_ results: SearchResults) -> some View {
        switch tab {
        case .albums:
            CardGrid(items: results.albums) { MediaCard($0) }
        case .artists:
            CardGrid(items: results.artists) { MediaCard($0) }
        default:
            CardGrid(items: results.playlists) { MediaCard($0) }
        }
    }

    private func load(force: Bool = false) async {
        await model.load("favorites", force: force, into: { state = $0 }) {
            try await model.library.favorites()
        }
    }
}
