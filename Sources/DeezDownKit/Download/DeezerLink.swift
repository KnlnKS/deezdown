import Foundation

public enum ArtistTab: String, Sendable, Equatable, CaseIterable, Codable {
    case all = "discography"
    case album
    case single
    case ep
    case compile
    case bundle
    case featured
    case more

    public var title: String {
        switch self {
        case .all: "Discography"
        case .album: "Albums"
        case .single: "Singles"
        case .ep: "EPs"
        case .compile: "Compilations"
        case .bundle: "Bundles"
        case .featured: "Featured In"
        case .more: "More"
        }
    }

    init?(path: String) {
        switch path {
        case "discography", "all": self = .all
        case "albums", "album": self = .album
        case "singles", "single": self = .single
        case "eps", "ep": self = .ep
        case "compile", "compilations": self = .compile
        case "bundle", "bundles": self = .bundle
        case "featured": self = .featured
        case "more": self = .more
        default: return nil
        }
    }
}

public enum DeezerLink: Sendable, Equatable, Hashable, Codable {
    case track(String)
    case album(String)
    case playlist(String)
    case artist(String, tab: ArtistTab)
    case artistTop(String)

    public var kind: String {
        switch self {
        case .track: "track"
        case .album: "album"
        case .playlist: "playlist"
        case .artist: "artist"
        case .artistTop: "artist_top"
        }
    }

    public var identifier: String {
        switch self {
        case .track(let id), .album(let id), .playlist(let id), .artistTop(let id): id
        case .artist(let id, let tab): "\(id)_\(tab.rawValue)"
        }
    }

    public var webURL: URL? {
        switch self {
        case .track(let id): URL(string: "https://www.deezer.com/track/\(id)")
        case .album(let id): URL(string: "https://www.deezer.com/album/\(id)")
        case .playlist(let id): URL(string: "https://www.deezer.com/playlist/\(id)")
        case .artistTop(let id): URL(string: "https://www.deezer.com/artist/\(id)/top_track")
        case .artist(let id, let tab): URL(string: "https://www.deezer.com/artist/\(id)/\(tab.rawValue)")
        }
    }
}

public enum LinkParseError: Error, Sendable, Equatable {
    case notRecognized(String)
    case notSupported(String)
    case invalidID(String)
}

public enum LinkParser {
    /// Splits pasted input the same way deemix's queue endpoint does.
    public static func split(_ input: String) -> [String] {
        input.split(whereSeparator: { $0.isWhitespace || $0 == ";" }).map(String.init)
    }

    public static func parse(_ input: String) throws -> DeezerLink {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mark = text.firstIndex(where: { $0 == "?" || $0 == "&" }) {
            text = String(text[text.startIndex..<mark])
        }
        if text.hasSuffix("/") { text.removeLast() }
        guard text.localizedCaseInsensitiveContains("deezer") else { throw LinkParseError.notRecognized(input) }

        if let id = capture(#"/track/(.+)$"#, in: text) {
            guard isValidTrackID(id) else { throw LinkParseError.invalidID(id) }
            return .track(id)
        }
        if let id = capture(#"/playlist/(\d+)"#, in: text) { return .playlist(id) }
        if let id = capture(#"/album/(.+)$"#, in: text) {
            guard isValidAlbumID(id) else { throw LinkParseError.invalidID(id) }
            return .album(id)
        }
        if let id = capture(#"/artist/(\d+)/top_track"#, in: text) { return .artistTop(id) }
        if let id = capture(#"/artist/(\d+)/(.+)$"#, in: text),
            let tail = capture(#"/artist/\d+/(.+)$"#, in: text)
        {
            guard let tab = ArtistTab(path: tail) else { throw LinkParseError.notSupported(input) }
            return .artist(id, tab: tab)
        }
        if let id = capture(#"/artist/(\d+)"#, in: text) { return .artist(id, tab: .all) }

        throw LinkParseError.notSupported(input)
    }

    /// Short links only reveal their target by following the redirect.
    public static func resolve(_ input: String, using session: URLSession = .shared) async throws -> DeezerLink {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains("deezer.page.link") || text.contains("dzr.page.link"),
            let url = URL(string: text)
        else { return try parse(text) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(DeezerSession.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await session.data(for: request), let final = response.url else {
            throw LinkParseError.notRecognized(input)
        }
        return try parse(final.absoluteString)
    }

    static func isValidTrackID(_ id: String) -> Bool {
        id.hasPrefix("isrc:") ? id.count > 5 : id.range(of: #"^-?\d+$"#, options: .regularExpression) != nil
    }

    static func isValidAlbumID(_ id: String) -> Bool {
        id.hasPrefix("upc:") ? id.count > 4 : id.range(of: #"^\d+$"#, options: .regularExpression) != nil
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
