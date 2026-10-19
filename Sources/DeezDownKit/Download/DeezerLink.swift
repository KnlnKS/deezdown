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

    /// Files a discography the way deezer-js does: the artist's own official releases under
    /// their record type, appearances as a featured artist apart, and other releases they
    /// lead under More. All holds everything but the featured appearances.
    static func sorting(_ discography: [JSONValue], artistID: String) -> [ArtistTab: [AlbumSummary]] {
        var tabs: [ArtistTab: [AlbumSummary]] = [:]
        for entry in discography {
            let album = AlbumSummary(gateway: entry)
            let role = entry["ROLE_ID"].intValue ?? 0
            let official = entry["ARTISTS_ALBUMS_IS_OFFICIAL"].boolValue ?? false
            let tab: ArtistTab? =
                if official && (album.artistID == artistID || role == 0) {
                    ArtistTab(rawValue: album.recordType.rawValue)
                } else if role == 5 {
                    .featured
                } else if role == 0 {
                    .more
                } else {
                    nil
                }
            guard let tab else { continue }
            tabs[tab, default: []].append(album)
            if tab != .featured { tabs[.all, default: []].append(album) }
        }
        return tabs
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

    public var placeholderTitle: String {
        switch self {
        case .track: "Track"
        case .album: "Album"
        case .playlist: "Playlist"
        case .artistTop: "Top Tracks"
        case .artist(_, let tab): tab.title
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

public enum LinkParseError: LocalizedError, Sendable, Equatable {
    case notRecognized(String)
    case notSupported(String)
    case invalidID(String)

    public var errorDescription: String? {
        switch self {
        case .notRecognized: "That doesn't look like a Deezer link."
        case .notSupported: "That kind of Deezer link isn't supported."
        case .invalidID(let id): "\"\(id)\" isn't a valid Deezer id."
        }
    }
}

public enum LinkParser {
    /// Splits pasted input the same way deemix's queue endpoint does.
    public static func split(_ input: String) -> [String] {
        input.split(whereSeparator: { $0.isWhitespace || $0 == ";" }).map(String.init)
    }

    /// Whether `resolve` can make a link of `input`, answered without going to the network.
    public static func isLink(_ input: String) -> Bool {
        isShortLink(input) || (try? parse(input)) != nil
    }

    private static func isShortLink(_ text: String) -> Bool {
        text.contains("deezer.page.link") || text.contains("dzr.page.link")
    }

    public static func parse(_ input: String) throws -> DeezerLink {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mark = text.firstIndex(where: { $0 == "?" || $0 == "&" }) {
            text = String(text[text.startIndex..<mark])
        }
        if text.hasSuffix("/") { text.removeLast() }
        guard text.localizedCaseInsensitiveContains("deezer") else { throw LinkParseError.notRecognized(input) }

        if let match = text.firstMatch(of: /\/track\/(.+)$/.ignoresCase()) {
            let id = String(match.1)
            guard isValidTrackID(id) else { throw LinkParseError.invalidID(id) }
            return .track(id)
        }
        if let match = text.firstMatch(of: /\/playlist\/(\d+)/.ignoresCase()) { return .playlist(String(match.1)) }
        if let match = text.firstMatch(of: /\/album\/(.+)$/.ignoresCase()) {
            let id = String(match.1)
            guard isValidAlbumID(id) else { throw LinkParseError.invalidID(id) }
            return .album(id)
        }
        if let match = text.firstMatch(of: /\/artist\/(\d+)\/top_track/.ignoresCase()) {
            return .artistTop(String(match.1))
        }
        if let match = text.firstMatch(of: /\/artist\/(\d+)(?:\/(.+))?$/.ignoresCase()) {
            guard let tab = match.2.map({ ArtistTab(path: String($0)) }) ?? .all else {
                throw LinkParseError.notSupported(input)
            }
            return .artist(String(match.1), tab: tab)
        }
        throw LinkParseError.notSupported(input)
    }

    /// Short links only reveal their target by following the redirect.
    public static func resolve(_ input: String, using session: URLSession = .shared) async throws -> DeezerLink {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isShortLink(text), let url = URL(string: text) else { return try parse(text) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(DeezerSession.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await session.data(for: request), let final = response.url else {
            throw LinkParseError.notRecognized(input)
        }
        return try parse(final.absoluteString)
    }

    /// A short link costs a redirect, so they are followed together; results keep the input order.
    public static func resolveAll(_ inputs: [String]) async -> [Result<DeezerLink, any Error>] {
        await withTaskGroup(of: (Int, Result<DeezerLink, any Error>).self) { group in
            for (index, input) in inputs.enumerated() {
                group.addTask {
                    do { return (index, .success(try await resolve(input))) } catch { return (index, .failure(error)) }
                }
            }
            var results = [Result<DeezerLink, any Error>?](repeating: nil, count: inputs.count)
            for await (index, result) in group { results[index] = result }
            return results.compactMap { $0 }
        }
    }

    static func isValidTrackID(_ id: String) -> Bool {
        id.hasPrefix("isrc:") ? id.count > 5 : id.range(of: #"^-?\d+$"#, options: .regularExpression) != nil
    }

    static func isValidAlbumID(_ id: String) -> Bool {
        id.hasPrefix("upc:") ? id.count > 4 : id.range(of: #"^\d+$"#, options: .regularExpression) != nil
    }
}
