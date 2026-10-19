import Foundation

public struct DeezerLibrary: Sendable {
    let session: DeezerSession

    public init(session: DeezerSession) {
        self.session = session
    }

    // MARK: - Search

    public func search(_ query: String, limit: Int = 12) async throws -> SearchResults {
        let page = try await session.searchAll(query: query, limit: limit)
        return SearchResults(
            tracks: page["TRACK"]["data"].arrayValue.map(TrackSummary.init(gateway:)),
            albums: page["ALBUM"]["data"].arrayValue.map(AlbumSummary.init(gateway:)),
            artists: page["ARTIST"]["data"].arrayValue.map(ArtistSummary.init(gateway:)),
            playlists: page["PLAYLIST"]["data"].arrayValue.map(PlaylistSummary.init(gateway:))
        )
    }

    public func search<Item: Searchable>(
        _ query: String, as type: Item.Type = Item.self, start: Int, limit: Int = 40
    ) async throws -> (items: [Item], total: Int) {
        let (items, total) = try await session.search(query: query, kind: Item.searchKind, start: start, limit: limit)
        return (items.map(Item.init(gateway:)), total)
    }

    // MARK: - Detail

    public func album(id: String) async throws -> AlbumDetail {
        async let pageTask = session.albumPage(id: id)
        async let entriesTask = session.albumTracks(id: id)
        async let publicTask = session.publicAPI("album/\(id)")
        let data = try await pageTask["DATA"]
        let tracks = try await entriesTask.map(TrackSummary.init(gateway:))
        let publicData = try? await publicTask

        var summary = AlbumSummary(gateway: data)
        if summary.trackCount == 0 { summary.trackCount = tracks.count }

        return AlbumDetail(
            summary: summary,
            tracks: tracks,
            artistPicture: data["ARTISTS"].arrayValue
                .first { $0["ART_ID"].stringValue == summary.artistID }?["ART_PICTURE"].stringValue
                ?? data["ART_PICTURE"].stringValue ?? "",
            label: data["LABEL_NAME"].stringValue ?? publicData?["label"].stringValue ?? "",
            genres: publicData?["genres"]["data"].arrayValue.compactMap { $0["name"].stringValue } ?? [],
            duration: tracks.reduce(0) { $0 + $1.duration },
            discTotal: data["NUMBER_DISK"].intValue ?? 1
        )
    }

    public func playlist(id: String) async throws -> PlaylistDetail {
        async let pageTask = session.playlistPage(id: id)
        async let entriesTask = session.playlistTracks(id: id)
        let data = try await pageTask["DATA"]
        let tracks = try await entriesTask.map(TrackSummary.init(gateway:))
        var summary = PlaylistSummary(gateway: data)
        if summary.trackCount == 0 { summary.trackCount = tracks.count }
        return PlaylistDetail(
            summary: summary, tracks: tracks, duration: tracks.reduce(0) { $0 + $1.duration }
        )
    }

    public func artist(id: String) async throws -> ArtistDetail {
        async let pageTask = session.artistPage(id: id)
        async let discographyTask = session.artistDiscography(id: id)
        let page = try await pageTask
        return ArtistDetail(
            summary: ArtistSummary(gateway: page["DATA"]),
            biography: page["BIO"]["BIO"].stringValue?.strippingHTML ?? "",
            topTracks: page["TOP"]["data"].arrayValue.map(TrackSummary.init(gateway:)),
            albums: ArtistTab.sorting(try await discographyTask, artistID: id)
        )
    }

    // MARK: - Personal

    public func favorites() async throws -> SearchResults {
        guard let user = await session.user else { throw DeezerError.notLoggedIn }
        async let tracksTask = session.profileTab(userID: user.id, tab: .loved)
        async let albumsTask = session.profileTab(userID: user.id, tab: .albums)
        async let artistsTask = session.profileTab(userID: user.id, tab: .artists)
        async let playlistsTask = session.profileTab(userID: user.id, tab: .playlists)
        return SearchResults(
            tracks: try await tracksTask.map(TrackSummary.init(gateway:)),
            albums: try await albumsTask.map(AlbumSummary.init(gateway:)),
            artists: try await artistsTask.map(ArtistSummary.init(gateway:)),
            playlists: try await playlistsTask.map(PlaylistSummary.init(gateway:))
        )
    }

    /// History is one entry per play, so a record the user sat with fills the whole row;
    /// collapsing to the album keeps it varied and matches how Deezer presents it.
    public func recentlyPlayed(limit: Int = 100) async throws -> [AlbumSummary] {
        var seen = Set<String>()
        return try await session.songsHistory(limit: limit)
            .map(AlbumSummary.init(gateway:))
            .filter { !$0.title.isEmpty && seen.insert($0.id).inserted }
    }

    /// Everything home shows, gathered at once. Only the charts are load-bearing: the personal
    /// rows drop out quietly if the account has nothing to show or the gateway declines.
    public func home() async throws -> HomeFeed {
        let userID = await session.user?.id ?? ""
        async let historyTask = recentlyPlayed()
        async let playlistsTask = session.profileTab(userID: userID, tab: .playlists)
        async let artistsTask = session.profileTab(userID: userID, tab: .artists)
        async let chartsTask = charts()

        let top = try await chartsTask
        return HomeFeed(
            history: (try? await historyTask) ?? [],
            playlists: ((try? await playlistsTask) ?? []).map(PlaylistSummary.init(gateway:)),
            artists: ((try? await artistsTask) ?? []).map(ArtistSummary.init(gateway:)),
            topAlbums: top.albums,
            topPlaylists: top.playlists
        )
    }

    // MARK: - Discovery

    public func charts() async throws -> SearchResults {
        let results = try await session.publicAPI("chart/0", query: ["limit": "30"])
        return SearchResults(
            tracks: [],
            albums: results["albums"]["data"].arrayValue.map(AlbumSummary.init(publicData:)),
            artists: [],
            playlists: results["playlists"]["data"].arrayValue.map(PlaylistSummary.init(publicData:))
        )
    }

    public func chartCountries() async throws -> [PlaylistSummary] {
        try await session.chartCountries().map(PlaylistSummary.init(publicData:))
    }
}

extension String {
    public var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .decodingHTMLEntities
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
