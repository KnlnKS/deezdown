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

public struct Picture: Sendable, Codable, Equatable, Hashable {
    public enum Kind: String, Sendable, Codable {
        case cover, artist, playlist, user, talk, misc
    }

    public var md5: String
    public var kind: Kind

    public init(md5: String, kind: Kind) {
        self.md5 = md5
        self.kind = kind
    }

    public var isEmpty: Bool { md5.isEmpty }

    public func url(size: Int, format: ImageFormat) -> URL? {
        guard !md5.isEmpty else { return nil }
        let suffix =
            switch format {
            case .jpeg(let quality): "-000000-\(quality)-0-0.jpg"
            case .png: "-none-100-0-0.png"
            }
        return URL(string: "https://e-cdns-images.dzcdn.net/images/\(kind.rawValue)/\(md5)/\(size)x\(size)\(suffix)")
    }

    /// Deezer degrades above 1200px and answers larger requests with an error.
    public static func clamped(_ size: Int) -> Int { min(size, 1200) }
}
