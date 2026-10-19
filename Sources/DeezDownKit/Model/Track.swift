import Foundation

public struct Track: Sendable, Equatable {
    public var id: String
    public var title: String
    public var duration: Int
    public var trackNumber: Int
    public var discNumber: Int
    public var position: Int?
    public var isrc: String
    public var bpm: Double
    public var gain: Double?
    public var rank: Int
    public var explicit: Bool
    public var copyright: String
    public var date: CustomDate?

    public var mainArtist: ArtistRef
    public var artistRefs: [ArtistRef]
    public var artists: [String]
    public var contributors: [String: [String]]

    public var album: Album
    public var playlist: Playlist?

    public var filesizes: [Int: Int]
    public var trackToken: String
    public var trackTokenExpires: Int
    public var md5Origin: String
    public var fallbackID: String?
    public var alternativeAlbumIDs: [String]
    public var lyricsID: String
    public var lyrics: Lyrics?

    public var searched = false

    public private(set) var artistsString = ""
    public private(set) var mainArtistsString = ""
    public private(set) var featuredArtistsString = ""
    public private(set) var fullArtistsString = ""

    public var isLocal: Bool { (Int(id) ?? 0) < 0 }
    public var isEncoded: Bool { !md5Origin.isEmpty && md5Origin != "0" }

    public func filesize(for format: TrackFormat) -> Int {
        filesizes[format.rawValue] ?? 0
    }

    public var tokenIsExpired: Bool {
        trackTokenExpires > 0 && Date().timeIntervalSince1970 > Double(trackTokenExpires)
    }

    init(gateway: JSONValue, album: Album? = nil, playlist: Playlist? = nil) {
        let refs = gateway["ARTISTS"].arrayValue.map(ArtistRef.init(gateway:))
        let main = refs.first { $0.role == .main } ?? refs.first ?? ArtistRef(gateway: gateway)

        id = gateway["SNG_ID"].stringValue ?? "0"
        title = (gateway["SNG_TITLE"].stringValue ?? "").withVersion(gateway["VERSION"].stringValue)
        duration = gateway["DURATION"].intValue ?? 0
        trackNumber = gateway["TRACK_NUMBER"].intValue ?? 1
        discNumber = gateway["DISK_NUMBER"].intValue ?? 1
        position = gateway["POSITION"].intValue ?? gateway["TRACK_POSITION"].intValue
        isrc = gateway["ISRC"].stringValue ?? ""
        bpm = gateway["BPM"].doubleValue ?? 0
        gain = gateway["GAIN"].doubleValue
        rank = gateway["RANK_SNG"].intValue ?? 0
        explicit = gateway.isExplicit("EXPLICIT_TRACK_CONTENT", else: "EXPLICIT_LYRICS")
        copyright = gateway["COPYRIGHT"].stringValue ?? ""
        date = CustomDate(deezerString: gateway["PHYSICAL_RELEASE_DATE"].stringValue)
            ?? CustomDate(deezerString: gateway["DIGITAL_RELEASE_DATE"].stringValue)

        mainArtist = main
        artistRefs = refs.isEmpty ? [main] : refs
        artists = Album.orderedNames(from: artistRefs)
        contributors = gateway["SNG_CONTRIBUTORS"].objectValue.mapValues { value in
            value.arrayValue.compactMap(\.stringValue)
        }

        self.album = album ?? Album(
            id: gateway["ALB_ID"].stringValue ?? "0",
            title: gateway["ALB_TITLE"].stringValue ?? "",
            mainArtist: main,
            artists: [main.name],
            cover: Artwork(md5: gateway["ALB_PICTURE"].stringValue ?? "", kind: .cover)
        )
        self.playlist = playlist

        var sizes: [Int: Int] = [:]
        for format in TrackFormat.allCases {
            if let value = gateway["FILESIZE_\(format.apiName)"].intValue, value > 0 { sizes[format.rawValue] = value }
        }
        filesizes = sizes

        trackToken = gateway["TRACK_TOKEN"].stringValue ?? ""
        trackTokenExpires = gateway["TRACK_TOKEN_EXPIRE"].intValue ?? 0
        md5Origin = gateway["MD5_ORIGIN"].stringValue ?? ""
        let fallback = gateway["FALLBACK"]["SNG_ID"].stringValue
        fallbackID = (fallback == nil || fallback == "0") ? nil : fallback
        alternativeAlbumIDs = gateway["ALBUM_FALLBACK"]["data"].arrayValue
            .filter {
                ($0["RIGHTS"]["STREAM_SUB_AVAILABLE"].boolValue ?? false)
                    || ($0["RIGHTS"]["STREAM_ADS_AVAILABLE"].boolValue ?? false)
            }
            .compactMap { $0["ALB_ID"].stringValue }
        lyricsID = gateway["LYRICS_ID"].stringValue ?? "0"
        if gateway["LYRICS"] != .null { lyrics = Lyrics(results: gateway["LYRICS"]) }
    }
}

extension Track {
    /// deemix's applySettings, step for step.
    public func applying(_ settings: DownloadSettings) -> Track {
        var track = self

        if settings.tags.savePlaylistAsCompilation, let playlist = track.playlist {
            track.album.makePlaylistCompilation(playlist)
            track.trackNumber = track.position ?? track.trackNumber
            track.discNumber = 1
        } else if let albumDate = track.album.date {
            track.date = albumDate
        }

        if !settings.albumVariousArtists, track.album.mainArtist.isVariousArtists {
            track.album.artists.removeAll { $0 == track.album.mainArtist.name }
        }

        if settings.removeDuplicateArtists {
            track.artists = Self.removingSubstringDuplicates(track.artists)
            track.artistRefs = track.artistRefs.filter { ref in track.artists.contains(ref.name) }
        }

        let movesFeatures = settings.featuredToTitle == .moveToTitle
        func names(_ role: ArtistRole) -> [String] {
            track.artistRefs.filter { $0.role == role }.map { settings.artistCasing.apply(to: $0.name) }
        }
        track.mainArtist.name = settings.artistCasing.apply(to: track.mainArtist.name)
        track.artists = track.artists.map(settings.artistCasing.apply(to:))
        let credits = names(.main)
        let main = credits.isEmpty ? [track.mainArtist.name] : credits
        let featured = names(.featured)
        track.mainArtistsString = Self.andCommaConcat(main)
        track.featuredArtistsString = featured.isEmpty ? "" : "feat. " + Self.andCommaConcat(featured)
        track.fullArtistsString =
            featured.isEmpty ? track.mainArtistsString : "\(track.mainArtistsString) \(track.featuredArtistsString)"

        switch settings.featuredToTitle {
        case .unchanged: break
        case .removeFromTitle:
            track.title = Self.removingFeatures(from: track.title)
        case .removeFromTitleAndAlbum:
            track.title = Self.removingFeatures(from: track.title)
            track.album.title = Self.removingFeatures(from: track.album.title)
        case .moveToTitle:
            if !featured.isEmpty, !track.title.lowercased().contains("feat.") {
                track.title += " (\(track.featuredArtistsString))"
            }
        }

        if settings.removeAlbumVersion, track.title.contains("Album Version") {
            track.title = track.title
                .replacingOccurrences(of: #" ?\(Album Version\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        track.title = settings.titleCasing.apply(to: track.title)

        // With the features moved into the title, the joined artist string credits only the
        // main artists.
        let credited = movesFeatures ? main : track.artists
        track.artistsString =
            switch settings.tags.multiArtistSeparator {
            case .standard: credited.joined(separator: ", ")
            case .mainOnly: track.mainArtist.name
            case .andFeat: movesFeatures ? track.mainArtistsString : track.fullArtistsString
            case let separator: credited.joined(separator: separator.rawValue)
            }
        return track
    }

    static func andCommaConcat(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " & " + names[names.count - 1]
    }

    /// Keeps the fuller of two names where one contains the other. deemix keeps the shorter,
    /// which turns "Daft Punk" and "Daft" into "Daft".
    static func removingSubstringDuplicates(_ names: [String]) -> [String] {
        names.enumerated()
            .filter { index, name in
                !names.enumerated().contains { otherIndex, other in
                    otherIndex != index && other.count >= name.count
                        && other.localizedCaseInsensitiveContains(name)
                        && (other.count > name.count || otherIndex < index)
                }
            }
            .map(\.element)
    }

    /// Bracketed credits go whole; a bare "feat. X" runs only up to the next bracket, so a
    /// "(Remix)" after it survives, as in deemix.
    static let featureMarkers: [NSRegularExpression] = [
        #"\s*[(\[](?:feat|ft)\.?[^)\]]*[)\]]"#,
        #"\s+(?:feat|ft)\.?\s[^(\[]*?(?=\s*[(\[]|$)"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    static func removingFeatures(from title: String) -> String {
        var output = title
        for marker in featureMarkers {
            output = marker.stringByReplacingMatches(
                in: output, range: NSRange(output.startIndex..., in: output), withTemplate: ""
            )
        }
        return output.trimmingCharacters(in: .whitespaces)
    }
}

extension TextCasing {
    public func apply(to text: String) -> String {
        switch self {
        case .unchanged: text
        case .lower: text.lowercased()
        case .upper: text.uppercased()
        // deemix's word split: unlike `capitalized`, "don't" and "jay-z" keep their lowercase tails.
        case .start:
            text.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: false)
                .map { word -> String in
                    guard let first = word.first else { return "" }
                    if word.count > 1, "({['\"".contains(first) {
                        return String(first) + word.dropFirst().prefix(1).uppercased() + word.dropFirst(2).lowercased()
                    }
                    return first.uppercased() + word.dropFirst().lowercased()
                }
                .joined(separator: " ")
        case .sentence:
            text.isEmpty ? text : text.prefix(1).uppercased() + text.dropFirst().lowercased()
        }
    }
}

extension String {
    /// deemix's title with its version: the version moves to the end, once.
    func withVersion(_ version: String?) -> String {
        let title = trimmingCharacters(in: .whitespaces)
        let version = (version ?? "").trimmingCharacters(in: .whitespaces)
        guard !version.isEmpty else { return title }
        guard let range = title.range(of: version) else { return "\(title) \(version)" }
        let short = title.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespaces)
        return "\(short) \(version)".trimmingCharacters(in: .whitespaces)
    }
}
