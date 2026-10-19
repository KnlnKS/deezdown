import Foundation

public enum RecordType: String, Sendable, CaseIterable {
    case single, album, compile, ep, bundle

    init(gatewayType: String?, publicType: String?) {
        switch publicType?.lowercased() {
        case "single": self = .single
        case "album": self = .album
        case "compile", "compilation": self = .compile
        case "ep": self = .ep
        case "bundle": self = .bundle
        default:
            self =
                switch gatewayType {
                case "0": .single
                case "1": .album
                case "2": .compile
                case "3": .ep
                case "4": .bundle
                default: .album
                }
        }
    }

    public var displayName: String {
        switch self {
        case .single: "Single"
        case .album: "Album"
        case .compile: "Compilation"
        case .ep: "EP"
        case .bundle: "Bundle"
        }
    }
}

public struct Album: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var mainArtist: ArtistRef
    public var artists: [String]
    public var cover: Artwork
    public var genres: [String]
    public var label: String
    public var barcode: String
    public var copyright: String
    public var recordType: RecordType
    public var date: CustomDate?
    public var trackTotal: Int
    public var discTotal: Int
    public var explicit: Bool
    public var isPlaylistCompilation = false

    public init(
        id: String, title: String, mainArtist: ArtistRef,
        artists: [String] = [], cover: Artwork = Artwork(md5: "", kind: .cover), genres: [String] = [],
        label: String = "Unknown", barcode: String = "Unknown", copyright: String = "",
        recordType: RecordType = .album, date: CustomDate? = nil, trackTotal: Int = 0, discTotal: Int = 1,
        explicit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.mainArtist = mainArtist
        self.artists = artists.isEmpty ? [mainArtist.name] : artists
        self.cover = cover
        self.genres = genres
        self.label = label
        self.barcode = barcode
        self.copyright = copyright
        self.recordType = recordType
        self.date = date
        self.trackTotal = trackTotal
        self.discTotal = discTotal
        self.explicit = explicit
    }

    init(gateway: JSONValue, publicData: JSONValue = .null) {
        // As in deemix, the album's artists come from the public API: the gateway's album data
        // names its main artist without a picture and lists no others.
        let contributors = publicData["contributors"].arrayValue.compactMap(ArtistRef.init(publicData:))
        let refs = contributors.isEmpty ? gateway["ARTISTS"].arrayValue.map(ArtistRef.init(gateway:)) : contributors
        let main =
            ArtistRef(publicData: publicData["artist"])
            ?? refs.first { $0.role == .main } ?? refs.first ?? ArtistRef(gateway: gateway)

        id = gateway["ALB_ID"].stringValue ?? publicData["id"].stringValue ?? "0"
        title = gateway["ALB_TITLE"].stringValue.map { $0.withVersion(gateway["VERSION"].stringValue) }
            ?? publicData["title"].stringValue ?? ""
        mainArtist = main
        artists = Album.orderedNames(from: refs.isEmpty ? [main] : refs)
        cover = Artwork(
            md5: gateway["ALB_PICTURE"].stringValue ?? publicData["md5_image"].stringValue ?? "",
            kind: .cover
        )
        genres = publicData["genres"]["data"].arrayValue.compactMap { $0["name"].stringValue }
        label = gateway["LABEL_NAME"].stringValue ?? publicData["label"].stringValue ?? "Unknown"
        barcode = gateway["UPC"].stringValue ?? publicData["upc"].stringValue ?? "Unknown"
        copyright = gateway["COPYRIGHT"].stringValue ?? ""
        recordType = RecordType(
            gatewayType: gateway["TYPE"].stringValue,
            publicType: publicData["record_type"].stringValue
        )
        date =
            CustomDate(deezerString: gateway["ORIGINAL_RELEASE_DATE"].stringValue)
            ?? CustomDate(deezerString: gateway["PHYSICAL_RELEASE_DATE"].stringValue)
            ?? CustomDate(deezerString: gateway["DIGITAL_RELEASE_DATE"].stringValue)
            ?? CustomDate(deezerString: publicData["release_date"].stringValue)
        trackTotal = gateway["NUMBER_TRACK"].intValue ?? publicData["nb_tracks"].intValue ?? 0
        discTotal = gateway["NUMBER_DISK"].intValue ?? 1
        explicit =
            (gateway["EXPLICIT_ALBUM_CONTENT"]["EXPLICIT_LYRICS_STATUS"].intValue ?? 0) == 1
            || (publicData["explicit_lyrics"].boolValue ?? false)
    }

    static func orderedNames(from refs: [ArtistRef]) -> [String] {
        var seen = Set<String>()
        return refs.compactMap { seen.insert($0.name.lowercased()).inserted ? $0.name : nil }
    }

    public mutating func makePlaylistCompilation(_ playlist: Playlist) {
        isPlaylistCompilation = true
        id = "pl_\(playlist.id)"
        title = playlist.title
        mainArtist = ArtistRef(id: ArtistRef.variousArtistsID, name: "Various Artists", role: .main)
        artists = [mainArtist.name]
        cover = playlist.picture
        label = ""
        barcode = ""
        recordType = .compile
        date = playlist.date
        trackTotal = playlist.trackCount
        discTotal = 1
        explicit = playlist.explicit
    }
}
