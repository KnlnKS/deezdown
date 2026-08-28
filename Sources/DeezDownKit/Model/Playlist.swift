import Foundation

public struct Playlist: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var description: String
    public var picture: Picture
    public var owner: String
    public var ownerID: String
    public var trackCount: Int
    public var duration: Int
    public var date: CustomDate?
    public var explicit: Bool
    public var isPublic: Bool
    public var isLovedTracks: Bool

    public init(
        id: String, title: String, description: String = "", picture: Picture = Picture(md5: "", kind: .playlist),
        owner: String = "", ownerID: String = "0", trackCount: Int = 0, duration: Int = 0,
        date: CustomDate? = nil, explicit: Bool = false, isPublic: Bool = true, isLovedTracks: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.picture = picture
        self.owner = owner
        self.ownerID = ownerID
        self.trackCount = trackCount
        self.duration = duration
        self.date = date
        self.explicit = explicit
        self.isPublic = isPublic
        self.isLovedTracks = isLovedTracks
    }

    init(gateway: JSONValue) {
        id = gateway["PLAYLIST_ID"].stringValue ?? "0"
        title = gateway["TITLE"].stringValue ?? ""
        description = gateway["DESCRIPTION"].stringValue ?? ""
        picture = Picture(
            md5: gateway["PLAYLIST_PICTURE"].stringValue ?? "",
            kind: Picture.Kind(rawValue: gateway["PICTURE_TYPE"].stringValue ?? "playlist") ?? .playlist
        )
        owner = gateway["PARENT_USERNAME"].stringValue ?? ""
        ownerID = gateway["PARENT_USER_ID"].stringValue ?? "0"
        trackCount = gateway["NB_SONG"].intValue ?? 0
        duration = gateway["DURATION"].intValue ?? 0
        date =
            CustomDate(deezerString: gateway["DATE_MOD"].stringValue)
            ?? CustomDate(deezerString: gateway["DATE_ADD"].stringValue)
            ?? CustomDate(deezerString: gateway["DATE_CREATE"].stringValue)
        explicit = (gateway["EXPLICIT_PLAYLIST_CONTENT"]["EXPLICIT_LYRICS_STATUS"].intValue ?? 0) == 1
        isPublic = (gateway["STATUS"].intValue ?? 0) == 0
        isLovedTracks = (gateway["TYPE"].intValue ?? 0) == 4
    }
}
