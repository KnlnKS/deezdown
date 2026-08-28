import DeezDownKit
import SwiftUI

struct SearchScreen: View {
    @Environment(AppModel.self) private var model
    var query: String

    @State private var tab: SearchTab = .all
    @State private var state: LoadState<SearchResults> = .loading
    @State private var loadedQuery = ""

    enum SearchTab: String, CaseIterable, Identifiable {
        case all, tracks, albums, artists, playlists
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView {
                    Label("Search Deezer", systemImage: "magnifyingglass")
                } description: {
                    Text("Find artists, albums, tracks and playlists — or paste a link to queue it directly.")
                }
            } else {
                AsyncContent(state: state, retry: { Task { await load(force: true) } }) { results in
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        resultsView(results)
                    }
                }
            }
        }
        .navigationTitle("Search")
        .toolbar {
            if !query.isEmpty {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $tab) {
                        ForEach(SearchTab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
        .task(id: query) { await load(force: false) }
    }

    @ViewBuilder
    private func resultsView(_ results: SearchResults) -> some View {
        switch tab {
        case .all:
            ScreenScroll {
                if !results.tracks.isEmpty {
                    SectionHeader("Tracks") { Button("See All") { tab = .tracks } }
                    VStack(spacing: 0) {
                        ForEach(Array(results.tracks.prefix(5).enumerated()), id: \.element.id) { _, track in
                            TrackRow(track: track, showsArtwork: true, showsAlbum: true)
                                .padding(.vertical, 2)
                        }
                    }
                }
                grids(results)
            }
        case .tracks:
            List {
                ForEach(Array(results.tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, index: index + 1, showsArtwork: true, showsAlbum: true)
                }
            }
            .listStyle(.inset)
        case .albums:
            ScreenScroll { albumGrid(results.albums) }
        case .artists:
            ScreenScroll { artistGrid(results.artists) }
        case .playlists:
            ScreenScroll { playlistGrid(results.playlists) }
        }
    }

    @ViewBuilder
    private func grids(_ results: SearchResults) -> some View {
        if !results.albums.isEmpty {
            SectionHeader("Albums") { Button("See All") { tab = .albums } }
            albumGrid(Array(results.albums.prefix(8)))
        }
        if !results.artists.isEmpty {
            SectionHeader("Artists") { Button("See All") { tab = .artists } }
            artistGrid(Array(results.artists.prefix(8)))
        }
        if !results.playlists.isEmpty {
            SectionHeader("Playlists") { Button("See All") { tab = .playlists } }
            playlistGrid(Array(results.playlists.prefix(8)))
        }
    }

    private func albumGrid(_ albums: [AlbumSummary]) -> some View {
        CardGrid(items: albums) { album in
            NavigationLink(value: Route.album(album.id)) {
                MediaCard(picture: album.cover, title: album.title, subtitle: album.artist, link: album.link)
            }
            .buttonStyle(.plain)
        }
    }

    private func artistGrid(_ artists: [ArtistSummary]) -> some View {
        CardGrid(items: artists) { artist in
            NavigationLink(value: Route.artist(artist.id)) {
                MediaCard(
                    picture: artist.picture, title: artist.name,
                    subtitle: "\(artist.fans.formatted()) fans", link: artist.link, circular: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func playlistGrid(_ playlists: [PlaylistSummary]) -> some View {
        CardGrid(items: playlists) { playlist in
            NavigationLink(value: Route.playlist(playlist.id)) {
                MediaCard(
                    picture: playlist.picture, title: playlist.title,
                    subtitle: "\(playlist.trackCount) tracks", link: playlist.link
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func load(force: Bool) async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard force || text != loadedQuery else { return }
        state = .loading
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        do {
            let results = try await model.library.search(text, limit: 24)
            guard !Task.isCancelled else { return }
            loadedQuery = text
            state = .loaded(results)
        } catch {
            state = .failed(model.message(for: error))
        }
    }
}
