import DeezDownKit
import SwiftUI

struct Page<Item: Identifiable & Sendable>: Sendable {
    var items: [Item] = []
    var total = 0
    var isLoading = false
    var loadedQuery = ""

    var hasMore: Bool { !items.isEmpty && items.count < total }

    mutating func reset(for query: String) {
        items = []
        total = 0
        loadedQuery = query
    }
}

struct SearchScreen: View {
    @Environment(AppModel.self) private var model
    @Binding var query: String
    @Binding var tab: SearchTab

    @State private var overview: LoadState<SearchResults> = .loading
    @State private var overviewQuery = ""
    @State private var tracks = Page<TrackSummary>()
    @State private var albums = Page<AlbumSummary>()
    @State private var artists = Page<ArtistSummary>()
    @State private var playlists = Page<PlaylistSummary>()
    @State private var field = SearchFieldProxy()

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            results
        }
        .navigationTitle("Search")
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in field.focus?() }
        .task(id: query) { await reload() }
        .task(id: tab) { await loadCurrentTab() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            SearchFieldHost(text: $query, proxy: $field, onSubmit: submit)

            if !trimmed.isEmpty {
                UnderlineTabs(
                    selection: $tab,
                    options: SearchTab.allCases.map { ($0, $0.title) }
                )
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var results: some View {
        if trimmed.isEmpty {
            ContentUnavailableView {
                Label("Search Deezer", systemImage: "magnifyingglass")
            } description: {
                Text("Find artists, albums, tracks and playlists — or paste a link to queue it directly.")
            }
        } else {
            switch tab {
            case .all: overviewResults
            case .tracks: trackResults
            case .albums: albumResults
            case .artists: artistResults
            case .playlists: playlistResults
            }
        }
    }

    // MARK: - All

    private var overviewResults: some View {
        AsyncContent(state: overview, retry: { Task { await reload(force: true) } }) { found in
            if found.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            } else {
                ScreenScroll {
                    if !found.tracks.isEmpty {
                        SectionHeader("Tracks") { PillButton(title: "View all") { tab = .tracks } }
                        VStack(spacing: 0) {
                            ForEach(found.tracks.prefix(5)) { track in
                                TrackRow(track: track, showsArtwork: true, showsAlbum: true)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    if !found.artists.isEmpty {
                        SectionHeader("Artists") { PillButton(title: "View all") { tab = .artists } }
                        artistGrid(Array(found.artists.prefix(6)))
                    }
                    if !found.albums.isEmpty {
                        SectionHeader("Albums") { PillButton(title: "View all") { tab = .albums } }
                        albumGrid(Array(found.albums.prefix(6)))
                    }
                    if !found.playlists.isEmpty {
                        SectionHeader("Playlists") { PillButton(title: "View all") { tab = .playlists } }
                        playlistGrid(Array(found.playlists.prefix(6)))
                    }
                }
            }
        }
    }

    // MARK: - Paged tabs

    private var trackResults: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.items.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, index: index + 1, showsArtwork: true, showsAlbum: true)
                        .padding(.vertical, 3)
                        .padding(.horizontal, Metrics.gutter)
                        .hoverHighlight(corner: 6)
                }
                loadMoreFooter(tracks.hasMore, isLoading: tracks.isLoading)
            }
            .padding(.vertical, 8)
        }
    }

    private var albumResults: some View {
        pagedGrid(albums.hasMore, isLoading: albums.isLoading) { albumGrid(albums.items) }
    }

    private var artistResults: some View {
        pagedGrid(artists.hasMore, isLoading: artists.isLoading) { artistGrid(artists.items) }
    }

    private var playlistResults: some View {
        pagedGrid(playlists.hasMore, isLoading: playlists.isLoading) { playlistGrid(playlists.items) }
    }

    private func pagedGrid(_ hasMore: Bool, isLoading: Bool, @ViewBuilder grid: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                grid()
                loadMoreFooter(hasMore, isLoading: isLoading)
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Appearing at the bottom of the scroll view is what pulls the next page in.
    @ViewBuilder
    private func loadMoreFooter(_ hasMore: Bool, isLoading: Bool) -> some View {
        if hasMore || isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .task { await loadMore() }
        }
    }

    // MARK: - Grids

    private func albumGrid(_ items: [AlbumSummary]) -> some View {
        CardGrid(items: items) { album in
            NavigationLink(value: Route.album(album.id)) {
                MediaCard(picture: album.cover, title: album.title, subtitle: album.artist, link: album.link)
            }
            .buttonStyle(.plain)
        }
    }

    private func artistGrid(_ items: [ArtistSummary]) -> some View {
        CardGrid(items: items) { artist in
            NavigationLink(value: Route.artist(artist.id)) {
                MediaCard(
                    picture: artist.picture, title: artist.name,
                    subtitle: "\(artist.fans.formatted()) fans", link: artist.link, circular: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func playlistGrid(_ items: [PlaylistSummary]) -> some View {
        CardGrid(items: items) { playlist in
            NavigationLink(value: Route.playlist(playlist.id)) {
                MediaCard(
                    picture: playlist.picture, title: playlist.title,
                    subtitle: "\(playlist.trackCount) tracks", link: playlist.link
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading

    private func submit() {
        guard !trimmed.isEmpty else { return }
        if let link = try? LinkParser.parse(trimmed) {
            Task { await model.enqueue(link) }
            query = ""
        }
    }

    private func reload(force: Bool = false) async {
        guard !trimmed.isEmpty else { return }
        guard force || trimmed != overviewQuery else { return }

        tracks.reset(for: trimmed)
        albums.reset(for: trimmed)
        artists.reset(for: trimmed)
        playlists.reset(for: trimmed)

        overview = .loading
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        do {
            let found = try await model.library.search(trimmed, limit: 24)
            guard !Task.isCancelled else { return }
            overviewQuery = trimmed
            overview = .loaded(found)
            await loadCurrentTab()
        } catch {
            overview = .failed(model.message(for: error))
        }
    }

    private func loadCurrentTab() async {
        guard !trimmed.isEmpty, tab != .all else { return }
        let empty =
            switch tab {
            case .tracks: tracks.items.isEmpty
            case .albums: albums.items.isEmpty
            case .artists: artists.items.isEmpty
            case .playlists: playlists.items.isEmpty
            case .all: false
            }
        if empty { await loadMore() }
    }

    private func loadMore() async {
        let text = trimmed
        guard !text.isEmpty else { return }

        do {
            switch tab {
            case .all:
                return
            case .tracks:
                guard !tracks.isLoading else { return }
                tracks.isLoading = true
                let (items, total) = try await model.library.searchTracks(text, start: tracks.items.count)
                guard text == trimmed else { return }
                tracks.items += items
                tracks.total = total
                tracks.isLoading = false
            case .albums:
                guard !albums.isLoading else { return }
                albums.isLoading = true
                let (items, total) = try await model.library.searchAlbums(text, start: albums.items.count)
                guard text == trimmed else { return }
                albums.items += items
                albums.total = total
                albums.isLoading = false
            case .artists:
                guard !artists.isLoading else { return }
                artists.isLoading = true
                let (items, total) = try await model.library.searchArtists(text, start: artists.items.count)
                guard text == trimmed else { return }
                artists.items += items
                artists.total = total
                artists.isLoading = false
            case .playlists:
                guard !playlists.isLoading else { return }
                playlists.isLoading = true
                let (items, total) = try await model.library.searchPlaylists(text, start: playlists.items.count)
                guard text == trimmed else { return }
                playlists.items += items
                playlists.total = total
                playlists.isLoading = false
            }
        } catch {
            tracks.isLoading = false
            albums.isLoading = false
            artists.isLoading = false
            playlists.isLoading = false
            model.show(Toast(message: model.message(for: error), kind: .failure))
        }
    }
}

enum SearchTab: String, CaseIterable, Identifiable {
    case all, tracks, albums, artists, playlists
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Lets the window's Find command reach the field that lives inside this screen.
@Observable
final class SearchFieldProxy {
    var focus: (() -> Void)?
}

private struct SearchFieldHost: View {
    @Binding var text: String
    @Binding var proxy: SearchFieldProxy
    var onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Artists, albums, tracks, or a Deezer link", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? Color.brand : Color.primary.opacity(0.08), lineWidth: focused ? 2 : 1)
        }
        .frame(maxWidth: 520)
        .animation(Motion.quick, value: focused)
        .onAppear {
            proxy.focus = { focused = true }
            focused = true
        }
    }
}
