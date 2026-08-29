import Foundation

public struct Track: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var version: String
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
    public var mediaVersion: String
    public var fallbackID: String?
    public var alternativeAlbumIDs: [String]
    public var lyricsID: String
    public var lyrics: Lyrics?
    public var previewURL: URL?

    public var searched = false

    public var artistsString = ""
    public var mainArtistsString = ""
    public var featuredArtistsString = ""
    public var fullArtistsString = ""
    public var dateString = ""

    public var isLocal: Bool { (Int(id) ?? 0) < 0 }
    public var isEncoded: Bool { !md5Origin.isEmpty && md5Origin != "0" }

    public var displayTitle: String {
        version.isEmpty ? title : "\(title) \(version)"
    }

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
        title = (gateway["SNG_TITLE"].stringValue ?? "").trimmingCharacters(in: .whitespaces)
        version = (gateway["VERSION"].stringValue ?? "").trimmingCharacters(in: .whitespaces)
        duration = gateway["DURATION"].intValue ?? 0
        trackNumber = gateway["TRACK_NUMBER"].intValue ?? 1
        discNumber = gateway["DISK_NUMBER"].intValue ?? 1
        position = gateway["POSITION"].intValue ?? gateway["TRACK_POSITION"].intValue
        isrc = gateway["ISRC"].stringValue ?? ""
        bpm = gateway["BPM"].doubleValue ?? 0
        gain = gateway["GAIN"].doubleValue
        rank = gateway["RANK"].intValue ?? 0
        explicit = (gateway["EXPLICIT_TRACK_CONTENT"]["EXPLICIT_LYRICS_STATUS"].intValue
            ?? gateway["EXPLICIT_LYRICS"].intValue ?? 0) == 1
        copyright = gateway["COPYRIGHT"].stringValue ?? ""
        date = CustomDate(deezerString: gateway["PHYSICAL_RELEASE_DATE"].stringValue)
            ?? CustomDate(deezerString: gateway["DIGITAL_RELEASE_DATE"].stringValue)

        mainArtist = main
        artistRefs = refs.isEmpty ? [main] : refs
        artists = Album.orderedNames(from: refs.isEmpty ? [main] : refs)
        contributors = gateway["SNG_CONTRIBUTORS"].objectValue.mapValues { value in
            value.arrayValue.compactMap(\.stringValue)
        }

        self.album = album ?? Album(
            id: gateway["ALB_ID"].stringValue ?? "0",
            title: gateway["ALB_TITLE"].stringValue ?? "",
            mainArtist: main,
            cover: Artwork(md5: gateway["ALB_PICTURE"].stringValue ?? "", kind: .cover)
        )
        self.playlist = playlist

        var sizes: [Int: Int] = [:]
        for format in TrackFormat.allCases {
            if let value = gateway[format.filesizeKey].intValue, value > 0 { sizes[format.rawValue] = value }
        }
        filesizes = sizes

        trackToken = gateway["TRACK_TOKEN"].stringValue ?? ""
        trackTokenExpires = gateway["TRACK_TOKEN_EXPIRE"].intValue ?? 0
        md5Origin = gateway["MD5_ORIGIN"].stringValue ?? ""
        mediaVersion = gateway["MEDIA_VERSION"].stringValue ?? "0"
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
        previewURL = gateway["MEDIA"].arrayValue
            .first { $0["TYPE"].stringValue == "preview" }
            .flatMap { URL(string: $0["HREF"].stringValue ?? "") }
    }
}

extension Track {
    public func applying(_ settings: DownloadSettings) -> Track {
        var track = self

        if settings.removeDuplicateArtists {
            track.artists = Self.removingSubstringDuplicates(track.artists)
            track.artistRefs = track.artistRefs.filter { ref in track.artists.contains(ref.name) }
        }

        let mainNames = track.artistRefs.filter { $0.role == .main }.map(\.name)
        let featuredNames = track.artistRefs.filter { $0.role == .featured }.map(\.name)
        track.mainArtistsString = Self.andCommaConcat(mainNames.isEmpty ? [track.mainArtist.name] : mainNames)
        track.featuredArtistsString = featuredNames.isEmpty ? "" : "feat. " + Self.andCommaConcat(featuredNames)
        track.fullArtistsString = Self.andCommaConcat(track.artists)
        track.artistsString =
            switch settings.tags.multiArtistSeparator {
            case .standard: track.artists.joined(separator: ", ")
            case .mainOnly: track.mainArtist.name
            case .andFeat:
                track.featuredArtistsString.isEmpty
                    ? track.mainArtistsString
                    : "\(track.mainArtistsString) \(track.featuredArtistsString)"
            case let separator: track.artists.joined(separator: separator.rawValue)
            }

        if settings.removeAlbumVersion {
            track.title = track.title.replacingOccurrences(of: " (Album Version)", with: "")
        }

        switch settings.featuredToTitle {
        case .unchanged: break
        case .removeFromTitle:
            track.title = Self.removingFeatures(from: track.title)
        case .removeFromTitleAndAlbum:
            track.title = Self.removingFeatures(from: track.title)
            track.album.title = Self.removingFeatures(from: track.album.title)
        case .moveToTitle:
            track.title = Self.removingFeatures(from: track.title)
            if !track.featuredArtistsString.isEmpty {
                track.title += " (\(track.featuredArtistsString))"
            }
        }

        track.title = settings.titleCasing.apply(to: track.title)
        track.album.title = settings.titleCasing.apply(to: track.album.title)
        track.artists = track.artists.map(settings.artistCasing.apply(to:))
        track.artistsString = settings.artistCasing.apply(to: track.artistsString)
        track.mainArtistsString = settings.artistCasing.apply(to: track.mainArtistsString)
        track.fullArtistsString = settings.artistCasing.apply(to: track.fullArtistsString)
        track.mainArtist.name = settings.artistCasing.apply(to: track.mainArtist.name)

        if !settings.albumVariousArtists, track.album.mainArtist.isVariousArtists {
            track.album.artists = track.album.artists.filter { $0 != track.album.mainArtist.name }
        }
        track.album.artistsString =
            settings.tags.singleAlbumArtist
            ? track.album.mainArtist.name
            : track.album.artists.joined(separator: ", ")

        let template = settings.dateFormat.rawValue
        track.dateString = (track.date ?? track.album.date)?.formatted(template) ?? ""
        track.album.dateString = track.album.date?.formatted(template) ?? ""

        if settings.tags.savePlaylistAsCompilation, let playlist = track.playlist {
            track.album.makePlaylistCompilation(playlist)
            track.trackNumber = track.position ?? track.trackNumber
            track.discNumber = 1
        }

        return track
    }

    static func andCommaConcat(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " & " + names[names.count - 1]
    }

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

    /// Compiled once: `replacingOccurrences(options: .regularExpression)` builds all six
    /// again for every track prepared.
    static let featureMarkers: [NSRegularExpression] = [
        #"\s*\(feat\.?[^)]*\)"#, #"\s*\(ft\.?[^)]*\)"#,
        #"\s*\[feat\.?[^\]]*\]"#, #"\s*\[ft\.?[^\]]*\]"#,
        #"\s+feat\.?\s.*$"#, #"\s+ft\.?\s.*$"#,
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
        case .start: text.capitalized
        case .sentence:
            text.isEmpty ? text : text.prefix(1).uppercased() + text.dropFirst().lowercased()
        }
    }
}
