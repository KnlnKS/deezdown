import Foundation

public struct ResolvedCollection: Sendable {
    public var title: String
    public var subtitle: String
    public var cover: Artwork
    public var tracks: [Track]
    public var playlist: Playlist?
    public var rootArtist: ArtistRef?
    public var isSingleTrack = false
}

public struct LinkResolver: Sendable {
    let session: DeezerSession

    public init(session: DeezerSession) {
        self.session = session
    }

    public func resolve(_ link: DeezerLink) async throws -> ResolvedCollection {
        switch link {
        case .track(let id): try await resolveTrack(id)
        case .album(let id): try await resolveAlbum(id)
        case .playlist(let id): try await resolvePlaylist(id)
        case .artistTop(let id): try await resolveArtistTop(id)
        case .artist: preconditionFailure("An artist link is queued as one entry per album")
        }
    }

    private func numericTrackID(_ id: String) async throws -> String {
        guard id.hasPrefix("isrc:") else { return id }
        let results = try await session.publicAPI("track/\(id)")
        guard let resolved = results["id"].stringValue, resolved != "0" else {
            throw DownloadFailure(.notOnDeezer)
        }
        return resolved
    }

    /// A UPC is looked up on the public API, whose answer is also the album's public entry.
    private func numericAlbumID(_ id: String) async throws -> (id: String, publicData: JSONValue?) {
        guard id.hasPrefix("upc:") else { return (id, nil) }
        let results = try await session.publicAlbum(upc: String(id.dropFirst(4)))
        guard let resolved = results["id"].stringValue, resolved != "0" else {
            throw DownloadFailure(.albumMissing)
        }
        return (resolved, results)
    }

    private func resolveTrack(_ rawID: String) async throws -> ResolvedCollection {
        let id = try await numericTrackID(rawID)
        let gateway = try await session.trackData(id: id)
        guard gateway["SNG_ID"].stringValue != nil else { throw DownloadFailure(.notOnDeezer) }

        let albumID = gateway["ALB_ID"].stringValue ?? "0"
        let album = albumID == "0" ? nil : try? await session.enrichedAlbum(id: albumID)
        let track = Track(gateway: gateway, album: album)

        return ResolvedCollection(
            title: track.title,
            subtitle: track.mainArtist.name,
            cover: track.album.cover,
            tracks: [track],
            isSingleTrack: true
        )
    }

    private func resolveAlbum(_ rawID: String) async throws -> ResolvedCollection {
        let (id, publicData) = try await numericAlbumID(rawID)
        async let albumTask = session.enrichedAlbum(id: id, publicData: publicData)
        async let entriesTask = session.albumTracks(id: id)
        var album = try await albumTask
        let entries = try await entriesTask
        guard !entries.isEmpty else { throw DownloadFailure(.albumMissing) }
        if album.trackTotal == 0 { album.trackTotal = entries.count }

        return ResolvedCollection(
            title: album.title,
            subtitle: album.mainArtist.name,
            cover: album.cover,
            tracks: entries.map { Track(gateway: $0, album: album) },
            // deemix downloads a one-track album as that track.
            isSingleTrack: entries.count == 1
        )
    }

    private func resolvePlaylist(_ id: String) async throws -> ResolvedCollection {
        async let pageTask = session.playlistPage(id: id)
        async let entriesTask = session.playlistTracks(id: id)
        let playlist = Playlist(gateway: try await pageTask["DATA"])
        let entries = try await entriesTask

        return ResolvedCollection(
            title: playlist.title,
            subtitle: playlist.owner,
            cover: playlist.picture,
            tracks: Self.ordered(entries, in: playlist),
            playlist: playlist
        )
    }

    private func resolveArtistTop(_ id: String) async throws -> ResolvedCollection {
        async let artistTask = session.artistData(id: id)
        async let entriesTask = session.artistTopTracks(id: id)
        let artist = ArtistRef(gateway: try await artistTask)
        let entries = try await entriesTask

        let playlist = Playlist(
            id: "\(id)_top_track",
            title: "\(artist.name) - Top Tracks",
            picture: artist.picture,
            owner: artist.name,
            ownerID: id,
            trackCount: entries.count
        )
        return ResolvedCollection(
            title: playlist.title,
            subtitle: artist.name,
            cover: artist.picture,
            tracks: Self.ordered(entries, in: playlist),
            playlist: playlist,
            rootArtist: artist
        )
    }

    private static func ordered(_ entries: [JSONValue], in playlist: Playlist) -> [Track] {
        entries.enumerated().map { index, entry in
            var track = Track(gateway: entry, playlist: playlist)
            track.position = index + 1
            return track
        }
    }

    /// The albums an artist's tab covers, as the discography already describes them. One
    /// request, and enough to name a queue entry — reading each tracklist is the queue's job.
    public func artistAlbums(_ id: String, tab: ArtistTab) async throws -> [AlbumSummary] {
        let albums = ArtistTab.sorting(try await session.artistDiscography(id: id), artistID: id)[tab] ?? []
        guard !albums.isEmpty else { throw DownloadFailure(.noReleases(tab)) }
        return albums
    }
}
