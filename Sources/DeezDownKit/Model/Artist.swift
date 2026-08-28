import Foundation

public enum ArtistRole: String, Sendable, Codable, Equatable {
    case main = "Main"
    case featured = "Featured"
    case other = "Other"

    init(roleID: Int?) {
        switch roleID {
        case 0: self = .main
        case 5: self = .featured
        default: self = .other
        }
    }
}

public struct ArtistRef: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var picture: Picture
    public var role: ArtistRole

    public init(id: String, name: String, picture: Picture = Picture(md5: "", kind: .artist), role: ArtistRole = .main) {
        self.id = id
        self.name = name
        self.picture = picture
        self.role = role
    }

    init(gateway: JSONValue) {
        id = gateway["ART_ID"].stringValue ?? "0"
        name = gateway["ART_NAME"].stringValue ?? ""
        picture = Picture(md5: gateway["ART_PICTURE"].stringValue ?? "", kind: .artist)
        role = ArtistRole(roleID: gateway["ROLE_ID"].intValue)
    }

    public static let variousArtistsID = "5080"
    public var isVariousArtists: Bool { id == Self.variousArtistsID }
}
