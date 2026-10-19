import Foundation

public struct Playlist: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var picture: Artwork
    public var owner: String
    public var ownerID: String
    public var trackCount: Int
    public var date: CustomDate?
    public var explicit: Bool

    public init(
        id: String, title: String, picture: Artwork = Artwork(md5: "", kind: .playlist),
        owner: String = "", ownerID: String = "0", trackCount: Int = 0, date: CustomDate? = nil, explicit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.picture = picture
        self.owner = owner
        self.ownerID = ownerID
        self.trackCount = trackCount
        self.date = date
        self.explicit = explicit
    }

    init(gateway: JSONValue) {
        id = gateway["PLAYLIST_ID"].stringValue ?? "0"
        title = gateway["TITLE"].stringValue ?? ""
        picture = Artwork(
            md5: gateway["PLAYLIST_PICTURE"].stringValue ?? "",
            kind: Artwork.Kind(rawValue: gateway["PICTURE_TYPE"].stringValue ?? "playlist") ?? .playlist
        )
        owner = gateway["PARENT_USERNAME"].stringValue ?? ""
        ownerID = gateway["PARENT_USER_ID"].stringValue ?? "0"
        trackCount = gateway["NB_SONG"].intValue ?? 0
        date =
            CustomDate(deezerString: gateway["DATE_ADD"].stringValue)
            ?? CustomDate(deezerString: gateway["DATE_CREATE"].stringValue)
            ?? CustomDate(deezerString: gateway["DATE_MOD"].stringValue)
        explicit = (gateway["EXPLICIT_PLAYLIST_CONTENT"]["EXPLICIT_LYRICS_STATUS"].intValue ?? 0) == 1
    }
}
