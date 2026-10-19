import Foundation

public enum ImageFormat: Sendable, Equatable {
    case jpeg(quality: Int)
    case png

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        }
    }
}

public struct Artwork: Sendable, Codable, Equatable, Hashable {
    public enum Kind: String, Sendable, Codable {
        case cover, artist, playlist, user, talk, misc
    }

    public var md5: String
    public var kind: Kind

    public init(md5: String, kind: Kind) {
        self.md5 = md5
        self.kind = kind
    }

    init(playlist gateway: JSONValue) {
        md5 = gateway["PLAYLIST_PICTURE"].stringValue ?? ""
        kind = Kind(rawValue: gateway["PICTURE_TYPE"].stringValue ?? "playlist") ?? .playlist
    }

    /// Deezer retired `e-cdns-images.dzcdn.net`; it now answers 403 for every request.
    static let host = "https://cdn-images.dzcdn.net"

    public var isEmpty: Bool { md5.isEmpty }

    public func url(size: Int, format: ImageFormat) -> URL? {
        guard !md5.isEmpty else { return nil }
        let suffix =
            switch format {
            case .jpeg(let quality): "-000000-\(quality)-0-0.jpg"
            case .png: "-none-100-0-0.png"
            }
        return URL(string: "\(Artwork.host)/images/\(kind.rawValue)/\(md5)/\(size)x\(size)\(suffix)")
    }

    /// The CDN serves covers up to 1800px; above 1200px some fail, and those fall back to 1200.
    public static let maximumSize = 1800
}
