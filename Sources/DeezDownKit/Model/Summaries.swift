import Foundation

public struct TrackSummary: Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var title: String
    public var version: String
    public var artist: String
    public var artistID: String
    public var album: String
    public var albumID: String
    public var cover: Artwork
    public var duration: Int
    public var explicit: Bool
    public var position: Int?
    public var discNumber: Int
    public var previewURL: URL?

    public var displayTitle: String { version.isEmpty ? title : "\(title) \(version)" }
    public var link: DeezerLink { .track(id) }

    init(gateway: JSONValue) {
        id = gateway["SNG_ID"].stringValue ?? "0"
        title = gateway["SNG_TITLE"].stringValue ?? ""
        version = gateway["VERSION"].stringValue ?? ""
        artist = gateway["ART_NAME"].stringValue ?? ""
        artistID = gateway["ART_ID"].stringValue ?? "0"
        album = gateway["ALB_TITLE"].stringValue ?? ""
        albumID = gateway["ALB_ID"].stringValue ?? "0"
        cover = Artwork(md5: gateway["ALB_PICTURE"].stringValue ?? "", kind: .cover)
        duration = gateway["DURATION"].intValue ?? 0
        explicit = (gateway["EXPLICIT_TRACK_CONTENT"]["EXPLICIT_LYRICS_STATUS"].intValue
            ?? gateway["EXPLICIT_LYRICS"].intValue ?? 0) == 1
        position = gateway["TRACK_POSITION"].intValue ?? gateway["TRACK_NUMBER"].intValue
        discNumber = gateway["DISK_NUMBER"].intValue ?? 1
        previewURL = gateway["MEDIA"].arrayValue
            .first { $0["TYPE"].stringValue == "preview" }
            .flatMap { URL(string: $0["HREF"].stringValue ?? "") }
    }
}

public struct AlbumSummary: Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var title: String
    public var artist: String
    public var artistID: String
    public var cover: Artwork
    public var trackCount: Int
    public var year: String
    public var explicit: Bool
    public var recordType: RecordType

    public var link: DeezerLink { .album(id) }

    init(gateway: JSONValue) {
        id = gateway["ALB_ID"].stringValue ?? "0"
        title = gateway["ALB_TITLE"].stringValue ?? ""
        artist = gateway["ART_NAME"].stringValue ?? ""
        artistID = gateway["ART_ID"].stringValue ?? "0"
        cover = Artwork(md5: gateway["ALB_PICTURE"].stringValue ?? "", kind: .cover)
        trackCount = gateway["NUMBER_TRACK"].intValue ?? 0
        year = String(
            (gateway["DIGITAL_RELEASE_DATE"].stringValue ?? gateway["PHYSICAL_RELEASE_DATE"].stringValue
                ?? gateway["ORIGINAL_RELEASE_DATE"].stringValue ?? "").prefix(4)
        )
        explicit = (gateway["EXPLICIT_ALBUM_CONTENT"]["EXPLICIT_LYRICS_STATUS"].intValue ?? 0) == 1
        recordType = RecordType(gatewayType: gateway["TYPE"].stringValue, publicType: nil)
    }

    init(publicData: JSONValue) {
        id = publicData["id"].stringValue ?? "0"
        title = publicData["title"].stringValue ?? ""
        artist = publicData["artist"]["name"].stringValue ?? ""
        artistID = publicData["artist"]["id"].stringValue ?? "0"
        cover = Artwork(md5: publicData["md5_image"].stringValue ?? "", kind: .cover)
        trackCount = publicData["nb_tracks"].intValue ?? 0
        year = String((publicData["release_date"].stringValue ?? "").prefix(4))
        explicit = publicData["explicit_lyrics"].boolValue ?? false
        recordType = RecordType(gatewayType: nil, publicType: publicData["record_type"].stringValue)
    }
}

public struct ArtistSummary: Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var picture: Artwork
    public var fans: Int
    public var albumCount: Int

    public var link: DeezerLink { .artist(id, tab: .all) }

    init(gateway: JSONValue) {
        id = gateway["ART_ID"].stringValue ?? "0"
        name = gateway["ART_NAME"].stringValue ?? ""
        picture = Artwork(md5: gateway["ART_PICTURE"].stringValue ?? "", kind: .artist)
        fans = gateway["NB_FAN"].intValue ?? 0
        albumCount = gateway["NB_ALBUM"].intValue ?? 0
    }
}

public struct PlaylistSummary: Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var title: String
    public var owner: String
    public var picture: Artwork
    public var trackCount: Int
    public var description: String

    public var link: DeezerLink { .playlist(id) }

    init(gateway: JSONValue) {
        id = gateway["PLAYLIST_ID"].stringValue ?? "0"
        title = gateway["TITLE"].stringValue ?? ""
        owner = gateway["PARENT_USERNAME"].stringValue ?? ""
        picture = Artwork(
            md5: gateway["PLAYLIST_PICTURE"].stringValue ?? "",
            kind: Artwork.Kind(rawValue: gateway["PICTURE_TYPE"].stringValue ?? "playlist") ?? .playlist
        )
        trackCount = gateway["NB_SONG"].intValue ?? 0
        description = gateway["DESCRIPTION"].stringValue ?? ""
    }

    init(publicData: JSONValue) {
        id = publicData["id"].stringValue ?? "0"
        title = publicData["title"].stringValue ?? ""
        owner = publicData["user"]["name"].stringValue ?? ""
        picture = Artwork(md5: publicData["md5_image"].stringValue ?? "", kind: .playlist)
        trackCount = publicData["nb_tracks"].intValue ?? 0
        description = publicData["description"].stringValue ?? ""
    }
}

public struct SearchResults: Sendable, Equatable {
    public var tracks: [TrackSummary] = []
    public var albums: [AlbumSummary] = []
    public var artists: [ArtistSummary] = []
    public var playlists: [PlaylistSummary] = []

    public var isEmpty: Bool {
        tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty
    }
}

public struct AlbumDetail: Sendable, Equatable {
    public var summary: AlbumSummary
    public var tracks: [TrackSummary]
    public var label: String
    public var genres: [String]
    public var releaseDate: String
    public var duration: Int
    public var discTotal: Int
}

public struct PlaylistDetail: Sendable, Equatable {
    public var summary: PlaylistSummary
    public var tracks: [TrackSummary]
    public var duration: Int
}

public struct ArtistDetail: Sendable, Equatable {
    public var summary: ArtistSummary
    public var biography: String
    public var topTracks: [TrackSummary]
    public var albums: [ArtistTab: [AlbumSummary]]
}

public struct TrackDetail: Sendable, Equatable {
    public var summary: TrackSummary
    public var isrc: String
    public var bpm: Double
    public var releaseDate: String
    public var availableFormats: [TrackFormat]
}
