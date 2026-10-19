import Foundation

public struct Playlist: Sendable, Equatable {
    public var id: String
    public var title: String
    public var picture = Artwork(md5: "", kind: .playlist)
    public var owner = ""
    public var ownerID = "0"
    public var trackCount = 0
    public var date: CustomDate?
    public var explicit = false
}

extension Playlist {
    init(gateway: JSONValue) {
        id = gateway["PLAYLIST_ID"].stringValue ?? "0"
        title = gateway["TITLE"].stringValue ?? ""
        picture = Artwork(playlist: gateway)
        owner = gateway["PARENT_USERNAME"].stringValue ?? ""
        ownerID = gateway["PARENT_USER_ID"].stringValue ?? "0"
        trackCount = gateway["NB_SONG"].intValue ?? 0
        date =
            CustomDate(deezerString: gateway["DATE_ADD"].stringValue)
            ?? CustomDate(deezerString: gateway["DATE_CREATE"].stringValue)
            ?? CustomDate(deezerString: gateway["DATE_MOD"].stringValue)
        explicit = gateway.isExplicit("EXPLICIT_PLAYLIST_CONTENT")
    }
}
