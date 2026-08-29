import Foundation

public struct ResolvedCollection: Sendable {
    public var link: DeezerLink
    public var title: String
    public var subtitle: String
    public var cover: Artwork
    public var tracks: [Track]
    public var album: Album?
    public var playlist: Playlist?
    public var rootArtist: ArtistRef?
    public var isSingleTrack: Bool
}

public struct LinkResolver: Sendable {
    let session: DeezerSession
    let settings: DownloadSettings

    public init(session: DeezerSession, settings: DownloadSettings) {
        self.session = session
        self.settings = settings
    }

    public func resolve(_ link: DeezerLink) async throws -> [ResolvedCollection] {
        switch link {
        case .track(let id): [try await resolveTrack(id, link: link)]
        case .album(let id): [try await resolveAlbum(id, link: link, rootArtist: nil)]
        case .playlist(let id): [try await resolvePlaylist(id, link: link)]
        case .artistTop(let id): [try await resolveArtistTop(id, link: link)]
        case .artist(let id, let tab): try await resolveArtist(id, tab: tab, link: link)
        }
    }

    private func numericTrackID(_ id: String) async throws -> String {
        guard id.hasPrefix("isrc:") else { return id }
        let results = try await session.publicTrack(isrc: String(id.dropFirst(5)))
        guard let resolved = results["id"].stringValue, resolved != "0" else {
            throw DownloadFailure(.notOnDeezer)
        }
        return resolved
    }

    private func numericAlbumID(_ id: String) async throws -> String {
        guard id.hasPrefix("upc:") else { return id }
        let results = try await session.publicAlbum(upc: String(id.dropFirst(4)))
        guard let resolved = results["id"].stringValue, resolved != "0" else {
            throw DownloadFailure(.albumMissing)
        }
        return resolved
    }

    private func resolveTrack(_ rawID: String, link: DeezerLink) async throws -> ResolvedCollection {
        let id = try await numericTrackID(rawID)
        let gateway = try await session.trackData(id: id)
        guard gateway["SNG_ID"].stringValue != nil else { throw DownloadFailure(.notOnDeezer) }

        let albumID = gateway["ALB_ID"].stringValue ?? "0"
        let album = albumID == "0" ? nil : try? await session.enrichedAlbum(id: albumID)
        let track = Track(gateway: gateway, album: album)

        return ResolvedCollection(
            link: link,
            title: track.displayTitle,
            subtitle: track.mainArtist.name,
            cover: track.album.cover,
            tracks: [track],
            album: album,
            isSingleTrack: true
        )
    }

    private func resolveAlbum(_ rawID: String, link: DeezerLink, rootArtist: ArtistRef?) async throws
        -> ResolvedCollection
    {
        let id = try await numericAlbumID(rawID)
        async let albumTask = session.enrichedAlbum(id: id)
        async let entriesTask = session.albumTracks(id: id)
        let album = try await albumTask
        let entries = try await entriesTask
        guard !entries.isEmpty else { throw DownloadFailure(.albumMissing) }

        var album2 = album
        if album2.trackTotal == 0 { album2.trackTotal = entries.count }
        let tracks = entries.map { Track(gateway: $0, album: album2) }

        return ResolvedCollection(
            link: link,
            title: album2.title,
            subtitle: album2.mainArtist.name,
            cover: album2.cover,
            tracks: tracks,
            album: album2,
            rootArtist: rootArtist,
            isSingleTrack: false
        )
    }

    private func resolvePlaylist(_ id: String, link: DeezerLink) async throws -> ResolvedCollection {
        async let pageTask = session.playlistPage(id: id)
        async let entriesTask = session.playlistTracks(id: id)
        let playlist = Playlist(gateway: try await pageTask["DATA"])
        let entries = try await entriesTask

        var tracks: [Track] = []
        tracks.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() {
            var track = Track(gateway: entry, playlist: playlist)
            track.position = index + 1
            tracks.append(track)
        }

        return ResolvedCollection(
            link: link,
            title: playlist.title,
            subtitle: playlist.owner,
            cover: playlist.picture,
            tracks: tracks,
            playlist: playlist,
            isSingleTrack: false
        )
    }

    private func resolveArtistTop(_ id: String, link: DeezerLink) async throws -> ResolvedCollection {
        async let artistTask = session.artistData(id: id)
        async let entriesTask = session.artistTopTracks(id: id)
        let artistData = try await artistTask
        let entries = try await entriesTask

        let artist = ArtistRef(gateway: artistData)
        let playlist = Playlist(
            id: "\(id)_top_track",
            title: "\(artist.name) - Top Tracks",
            picture: artist.picture,
            owner: artist.name,
            ownerID: id,
            trackCount: entries.count
        )
        var tracks: [Track] = []
        for (index, entry) in entries.enumerated() {
            var track = Track(gateway: entry, playlist: playlist)
            track.position = index + 1
            tracks.append(track)
        }

        return ResolvedCollection(
            link: link,
            title: playlist.title,
            subtitle: artist.name,
            cover: artist.picture,
            tracks: tracks,
            playlist: playlist,
            rootArtist: artist,
            isSingleTrack: false
        )
    }

    /// The albums an artist's tab covers, as the discography already describes them. One
    /// request, and enough to name a queue entry — reading each tracklist is the queue's job.
    public func artistAlbums(_ id: String, tab: ArtistTab) async throws -> [AlbumSummary] {
        let discography = try await session.artistDiscography(id: id)
        let selected = discography.filter { entry in
            let isOfficial = entry["ARTISTS_ALBUMS_IS_OFFICIAL"].boolValue ?? false
            let role = entry["ROLE_ID"].intValue ?? 0
            let type = RecordType(gatewayType: entry["TYPE"].stringValue, publicType: nil)
            return switch tab {
            case .all: true
            case .featured: role == 5
            case .more: !isOfficial && role != 5
            default: isOfficial && role != 5 && type.rawValue == tab.rawValue
            }
        }
        guard !selected.isEmpty else { throw DownloadFailure(.albumMissing) }
        return selected.map(AlbumSummary.init(gateway:))
    }

    private func resolveArtist(_ id: String, tab: ArtistTab, link: DeezerLink) async throws
        -> [ResolvedCollection]
    {
        let artist = ArtistRef(gateway: try await session.artistData(id: id))
        var collections: [ResolvedCollection] = []
        for album in try await artistAlbums(id, tab: tab) {
            guard
                let collection = try? await resolveAlbum(
                    album.id, link: .album(album.id), rootArtist: artist
                )
            else { continue }
            collections.append(collection)
        }
        return collections
    }
}
