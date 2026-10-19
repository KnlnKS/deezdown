import DeezDownKit
import SwiftUI

struct Page<Item: Identifiable & Sendable>: Sendable {
    static var size: Int { 40 }

    var items: [Item] = []
    var isLoading = false
    var isExhausted = false

    /// Deezer's reported total overshoots what it will actually serve, so a short page —
    /// not the counter — is what marks the end.
    var hasMore: Bool { !isExhausted }

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

struct SearchScreen: View {
    @Environment(AppModel.self) private var model
    @Binding var query: String
    /// The kind of result a tab pages through; `nil` is the overview.
    @Binding var tab: SearchKind?

    @State private var overview: LoadState<SearchResults> = .loading
    @State private var overviewQuery = ""
    @State private var tracks = Page<TrackSummary>()
    @State private var albums = Page<AlbumSummary>()
    @State private var artists = Page<ArtistSummary>()
    @State private var playlists = Page<PlaylistSummary>()
    @FocusState private var searchFocused: Bool

    private static let tabs: [SearchKind?] = [nil] + SearchKind.allCases

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
                UnderlineTabs(selection: $tab, options: Self.tabs.map { ($0, $0?.title ?? "All") })
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
            case nil: overviewResults
            case .track:
                paged(tracks) {
                    ForEach(Array(tracks.items.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, index: index + 1, showsArtwork: true, showsAlbum: true)
                            .padding(.vertical, 3)
                            .padding(.horizontal, Metrics.gutter)
                            .hoverHighlight(corner: 6)
                    }
                }
            case .album: paged(albums) { CardGrid(items: albums.items) { MediaCard($0) }.padding(Metrics.gutter) }
            case .artist: paged(artists) { CardGrid(items: artists.items) { MediaCard($0) }.padding(Metrics.gutter) }
            case .playlist:
                paged(playlists) { CardGrid(items: playlists.items) { MediaCard($0) }.padding(Metrics.gutter) }
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

    // MARK: - Paged tabs

    /// The stack is lazy, so the footer appears, and pulls in the next page, only once scrolled
    /// to; keying its task on the item count fires it again for each new page.
    private func paged<Item>(_ page: Page<Item>, @ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                content()
                if page.hasMore {
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

    // MARK: - Loading

    private func submit() {
        guard LinkParser.isLink(trimmed) else { return }
        let pasted = trimmed
        Task { await model.enqueue(pasted: pasted) }
        query = ""
    }

    private func reload(force: Bool = false) async {
        guard !trimmed.isEmpty else { return }
        guard force || trimmed != overviewQuery else { return }

        tracks = Page()
        albums = Page()
        artists = Page()
        playlists = Page()

        overview = .loading
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        do {
            // Only the tracks follow the limit, and the overview shows five.
            let found = try await model.library.search(trimmed, limit: 5)
            guard !Task.isCancelled else { return }
            overviewQuery = trimmed
            overview = .loaded(found)
            await loadCurrentTab()
        } catch {
            guard !Task.isCancelled else { return }
            overview = .failed(error.localizedDescription)
        }
    }

    private func loadCurrentTab() async {
        guard !trimmed.isEmpty, let tab else { return }
        let empty =
            switch tab {
            case .track: tracks.items.isEmpty
            case .album: albums.items.isEmpty
            case .artist: artists.items.isEmpty
            case .playlist: playlists.items.isEmpty
            }
        if empty { await loadMore() }
    }

    private func loadMore() async {
        switch tab {
        case nil: break
        case .track: await extend(tracks) { tracks = $0 }
        case .album: await extend(albums) { albums = $0 }
        case .artist: await extend(artists) { artists = $0 }
        case .playlist: await extend(playlists) { playlists = $0 }
        }
    }

    /// Every tab pages the same way; only the kind of result it asks for differs.
    private func extend<Item: Searchable>(_ page: Page<Item>, store: (Page<Item>) -> Void) async {
        let query = trimmed
        guard !query.isEmpty, !page.isLoading, page.hasMore else { return }
        var page = page
        page.isLoading = true
        store(page)

        do {
            let (items, total) = try await model.library.search(query, as: Item.self, start: page.items.count, limit: Page<Item>.size)
            guard query == trimmed else { return }
            page.append(items, total: total)
        } catch {
            guard query == trimmed else { return }
            page.isLoading = false
            // A failed page ends the run rather than spinning forever; leaving the tab only
            // pauses it.
            if !Task.isCancelled {
                page.isExhausted = true
                model.show(Toast(message: error.localizedDescription, kind: .failure))
            }
        }
        store(page)
    }
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
