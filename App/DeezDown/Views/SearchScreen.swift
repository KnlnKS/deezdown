import DeezDownKit
import SwiftUI

struct Page<Item: Identifiable & Sendable>: Sendable {
    static var size: Int { 40 }

    var items: [Item] = []
    var total = 0
    var isLoading = false
    var isExhausted = false

    /// Deezer's reported total overshoots what it will actually serve, so a short page —
    /// not the counter — is what marks the end.
    var hasMore: Bool { !isExhausted }

    mutating func reset() {
        items = []
        total = 0
        isExhausted = false
        isLoading = false
    }

    mutating func append(_ incoming: [Item], total reported: Int) {
        let seen = Set(items.map(\.id))
        let fresh = incoming.filter { !seen.contains($0.id) }
        items += fresh
        total = reported
        if incoming.count < Self.size || fresh.isEmpty || items.count >= reported {
            isExhausted = true
        }
        isLoading = false
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
    @FocusState private var searchFocused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            controls
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            results
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Search")
        .onChange(of: model.command) { _, command in
            if command?.kind == .findInSearch { searchFocused = true }
        }
        .task(id: query) { await reload() }
        .task(id: tab) { await loadCurrentTab() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            SearchField(text: $query, focused: $searchFocused, onSubmit: submit)

            if !trimmed.isEmpty {
                UnderlineTabs(
                    selection: $tab,
                    options: SearchTab.allCases.map { ($0, $0.title) }
                )
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 16)
        .padding(.bottom, 8)
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
                loadMoreFooter(tracks.hasMore, count: tracks.items.count)
            }
            .padding(.vertical, 8)
        }
    }

    private var albumResults: some View {
        pagedGrid(albums.hasMore, count: albums.items.count) { albumGrid(albums.items) }
    }

    private var artistResults: some View {
        pagedGrid(artists.hasMore, count: artists.items.count) { artistGrid(artists.items) }
    }

    private var playlistResults: some View {
        pagedGrid(playlists.hasMore, count: playlists.items.count) { playlistGrid(playlists.items) }
    }

    private func pagedGrid(_ hasMore: Bool, count: Int, @ViewBuilder grid: @escaping () -> some View) -> some View {
        ScreenScroll {
            grid()
            loadMoreFooter(hasMore, count: count)
        }
    }

    /// Appearing at the bottom of the scroll view is what pulls the next page in; keying the
    /// task on the item count makes it fire again for each new page, and only while more exist.
    @ViewBuilder
    private func loadMoreFooter(_ hasMore: Bool, count: Int) -> some View {
        if hasMore {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .task(id: count) { await loadMore() }
        }
    }

    // MARK: - Grids

    private func albumGrid(_ items: [AlbumSummary]) -> some View {
        CardGrid(items: items) { MediaCard($0) }
    }

    private func artistGrid(_ items: [ArtistSummary]) -> some View {
        CardGrid(items: items) { MediaCard($0) }
    }

    private func playlistGrid(_ items: [PlaylistSummary]) -> some View {
        CardGrid(items: items) { MediaCard($0) }
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

        tracks.reset()
        albums.reset()
        artists.reset()
        playlists.reset()

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
        let library = model.library
        switch tab {
        case .all: break
        case .tracks: await extend(tracks, text, { tracks = $0 }, library.searchTracks)
        case .albums: await extend(albums, text, { albums = $0 }, library.searchAlbums)
        case .artists: await extend(artists, text, { artists = $0 }, library.searchArtists)
        case .playlists: await extend(playlists, text, { playlists = $0 }, library.searchPlaylists)
        }
    }

    /// Every tab pages the same way; only the endpoint it asks differs.
    private func extend<Item>(
        _ page: Page<Item>,
        _ query: String,
        _ store: (Page<Item>) -> Void,
        _ fetch: (String, Int, Int) async throws -> ([Item], Int)
    ) async {
        guard !page.isLoading, page.hasMore else { return }
        var page = page
        page.isLoading = true
        store(page)

        do {
            let (items, total) = try await fetch(query, page.items.count, Page<Item>.size)
            guard query == trimmed else { return }
            page.append(items, total: total)
        } catch {
            // A failed page ends the run rather than spinning forever.
            page.isExhausted = true
            page.isLoading = false
            model.show(Toast(message: model.message(for: error), kind: .failure))
        }
        store(page)
    }
}

enum SearchTab: String, CaseIterable, Identifiable {
    case all, tracks, albums, artists, playlists
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct SearchField: View {
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    var onSubmit: () -> Void

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
        .onAppear { focused = true }
    }
}
