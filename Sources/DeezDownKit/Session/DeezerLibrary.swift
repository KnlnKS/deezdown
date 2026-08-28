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

    public func searchTracks(_ query: String, start: Int, limit: Int = 40) async throws -> (
        [TrackSummary], Int
    ) {
        let (items, total) = try await session.search(query: query, kind: .track, start: start, limit: limit)
        return (items.map(TrackSummary.init(gateway:)), total)
    }

    public func searchAlbums(_ query: String, start: Int, limit: Int = 40) async throws -> (
        [AlbumSummary], Int
    ) {
        let (items, total) = try await session.search(query: query, kind: .album, start: start, limit: limit)
        return (items.map(AlbumSummary.init(gateway:)), total)
    }

    public func searchArtists(_ query: String, start: Int, limit: Int = 40) async throws -> (
        [ArtistSummary], Int
    ) {
        let (items, total) = try await session.search(query: query, kind: .artist, start: start, limit: limit)
        return (items.map(ArtistSummary.init(gateway:)), total)
    }

    public func searchPlaylists(_ query: String, start: Int, limit: Int = 40) async throws -> (
        [PlaylistSummary], Int
    ) {
        let (items, total) = try await session.search(query: query, kind: .playlist, start: start, limit: limit)
        return (items.map(PlaylistSummary.init(gateway:)), total)
    }

    // MARK: - Detail

    public func album(id: String) async throws -> AlbumDetail {
        async let pageTask = session.albumPage(id: id)
        async let entriesTask = session.albumTracks(id: id)
        let page = try await pageTask
        let data = page["DATA"]
        let entries = try await entriesTask
        let tracks = entries.map(TrackSummary.init(gateway:))

        var summary = AlbumSummary(gateway: data)
        if summary.trackCount == 0 { summary.trackCount = tracks.count }
        let publicData = try? await session.publicAPI("album/\(id)")

        return AlbumDetail(
            summary: summary,
            tracks: tracks,
            artistPicture: data["ARTISTS"].arrayValue
                .first { $0["ART_ID"].stringValue == summary.artistID }?["ART_PICTURE"].stringValue
                ?? data["ART_PICTURE"].stringValue ?? "",
            label: data["LABEL_NAME"].stringValue ?? publicData?["label"].stringValue ?? "",
            genres: publicData?["genres"]["data"].arrayValue.compactMap { $0["name"].stringValue } ?? [],
            releaseDate: data["ORIGINAL_RELEASE_DATE"].stringValue
                ?? data["DIGITAL_RELEASE_DATE"].stringValue ?? "",
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
        let discography = try await discographyTask

        var albums: [ArtistTab: [AlbumSummary]] = [:]
        albums[.all] = discography.map(AlbumSummary.init(gateway:))
        for tab in ArtistTab.allCases where tab != .all {
            let filtered = discography.filter { entry in
                let official = entry["ARTISTS_ALBUMS_IS_OFFICIAL"].boolValue ?? false
                let role = entry["ROLE_ID"].intValue ?? 0
                let type = RecordType(gatewayType: entry["TYPE"].stringValue, publicType: nil)
                return switch tab {
                case .featured: role == 5
                case .more: !official && role != 5
                default: official && role != 5 && type.rawValue == tab.rawValue
                }
            }
            if !filtered.isEmpty { albums[tab] = filtered.map(AlbumSummary.init(gateway:)) }
        }

        return ArtistDetail(
            summary: ArtistSummary(gateway: page["DATA"]),
            biography: page["BIO"]["BIO"].stringValue?.strippingHTML ?? "",
            topTracks: page["TOP"]["data"].arrayValue.map(TrackSummary.init(gateway:)),
            albums: albums
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

    public func lovedTracksLink() async -> DeezerLink? {
        guard let user = await session.user, !user.lovedTracksID.isEmpty else { return nil }
        return .playlist(user.lovedTracksID)
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
