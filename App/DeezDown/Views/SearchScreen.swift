import DeezDownKit
import SwiftUI

struct SearchScreen: View {
    @Environment(Navigator.self) private var navigator

    /// The kind of result a tab pages through; `nil` is the overview.
    @State private var tab: SearchKind?

    private static let tabs: [SearchKind?] = [nil] + SearchKind.allCases

    private var query: String { navigator.query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        if query.isEmpty {
            ContentUnavailableView {
                Label("Search Deezer", systemImage: "magnifyingglass")
            } description: {
                Text("Find artists, albums, tracks and playlists — or paste a link to queue it directly.")
            }
            .blendsWithToolbar()
        } else {
            TabbedPage(selection: $tab, options: Self.tabs.map { ($0, $0?.title ?? "All") }) {
                SearchResults(query: query, tab: $tab).id(query)
            }
        }
    }
}

/// Each request first waits out a burst of typing, so a keystroke isn't one. Waiting inside the
/// load, not before showing the results, puts up the spinner or anything cached at once.
private let typingPause = Duration.milliseconds(220)

/// One query's results. A new query gets a new view, so nothing still loading for the last one
/// can land here.
private struct SearchResults: View {
    var query: String
    @Binding var tab: SearchKind?

    @State private var tracks = Page<TrackSummary>()
    @State private var albums = Page<AlbumSummary>()
    @State private var artists = Page<ArtistSummary>()
    @State private var playlists = Page<PlaylistSummary>()

    var body: some View {
        switch tab {
        case nil: overview
        case .track:
            PagedResults(query: query, page: $tracks) { tracks in
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, index: index + 1, showsArtwork: true, showsAlbum: true)
                        .padding(.vertical, 3)
                        .padding(.horizontal, Metrics.gutter)
                        .hoverHighlight(corner: 6)
                }
            }
        case .album: PagedResults(query: query, page: $albums) { CardGrid(items: $0) { MediaCard($0) }.padding(Metrics.gutter) }
        case .artist: PagedResults(query: query, page: $artists) { CardGrid(items: $0) { MediaCard($0) }.padding(Metrics.gutter) }
        case .playlist:
            PagedResults(query: query, page: $playlists) { CardGrid(items: $0) { MediaCard($0) }.padding(Metrics.gutter) }
        }
    }

    private var overview: some View {
        Fetched("search-\(query)") { library in
            try await Task.sleep(for: typingPause)
            // Only the tracks follow the limit, and the overview shows five.
            return try await library.search(query, limit: 5)
        } content: { found in
            if found.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScreenScroll {
                    if !found.tracks.isEmpty {
                        SectionHeader("Tracks") { PillButton(title: "View all") { tab = .track } }
                        VStack(spacing: 0) {
                            ForEach(found.tracks.prefix(5)) { track in
                                TrackRow(track: track, showsArtwork: true, showsAlbum: true)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    if !found.artists.isEmpty {
                        SectionHeader("Artists") { PillButton(title: "View all") { tab = .artist } }
                        CardGrid(items: Array(found.artists.prefix(6))) { MediaCard($0) }
                    }
                    if !found.albums.isEmpty {
                        SectionHeader("Albums") { PillButton(title: "View all") { tab = .album } }
                        CardGrid(items: Array(found.albums.prefix(6))) { MediaCard($0) }
                    }
                    if !found.playlists.isEmpty {
                        SectionHeader("Playlists") { PillButton(title: "View all") { tab = .playlist } }
                        CardGrid(items: Array(found.playlists.prefix(6))) { MediaCard($0) }
                    }
                }
            }
        }
    }
}

private struct Page<Item: Identifiable> {
    static var size: Int { 40 }

    var items: [Item] = []
    var isLoading = false
    /// Deezer's reported total overshoots what it will actually serve, so a short page —
    /// not the counter — is what marks the end.
    var isExhausted = false

    mutating func append(_ incoming: [Item], total reported: Int) {
        let seen = Set(items.map(\.id))
        let fresh = incoming.filter { !seen.contains($0.id) }
        items += fresh
        if incoming.count < Self.size || fresh.isEmpty || items.count >= reported {
            isExhausted = true
        }
        isLoading = false
    }
}

/// A tab's results, a page at a time. The stack is lazy, so the footer appears, and pulls in the
/// next page, only once scrolled to; keying its task on the item count fires it again for each page.
private struct PagedResults<Item: Searchable, Content: View>: View {
    @Environment(AppModel.self) private var model
    var query: String
    @Binding var page: Page<Item>
    @ViewBuilder var content: ([Item]) -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                content(page.items)
                if !page.isExhausted {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .task(id: page.items.count) { await loadMore() }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func loadMore() async {
        guard !page.isLoading else { return }
        page.isLoading = true
        do {
            if page.items.isEmpty { try await Task.sleep(for: typingPause) }
            let (items, total) = try await model.library.search(
                query, as: Item.self, start: page.items.count, limit: Page<Item>.size
            )
            page.append(items, total: total)
        } catch {
            page.isLoading = false
            // A failed page ends the run rather than spinning forever; leaving the tab only
            // pauses it.
            if !Task.isCancelled {
                page.isExhausted = true
                model.show(Toast(message: error.localizedDescription, kind: .failure))
            }
        }
    }
}
