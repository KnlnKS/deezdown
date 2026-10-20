import Foundation

public enum OverwriteMode: String, Sendable, Codable, CaseIterable {
    case overwrite = "y"
    case skip = "n"
    case tagsOnly = "t"
    case keepBoth = "b"
    case skipAnyExtension = "e"
    case upgradeBitrate = "l"

    public var title: String {
        switch self {
        case .overwrite: "Overwrite the file"
        case .skip: "Don't overwrite"
        case .tagsOnly: "Update tags only"
        case .keepBoth: "Keep both files"
        case .skipAnyExtension: "Don't overwrite, ignoring extension"
        case .upgradeBitrate: "Overwrite only to upgrade bitrate"
        }
    }
}

public enum FeaturedTitleMode: String, Sendable, Codable, CaseIterable {
    case unchanged = "0"
    case removeFromTitle = "1"
    case moveToTitle = "2"
    case removeFromTitleAndAlbum = "3"

    public var title: String {
        switch self {
        case .unchanged: "Leave as-is"
        case .removeFromTitle: "Remove from track title"
        case .moveToTitle: "Move into track title"
        case .removeFromTitleAndAlbum: "Remove from track and album title"
        }
    }
}

public enum TextCasing: String, Sendable, Codable, CaseIterable {
    case unchanged = "nothing"
    case lower, upper, start, sentence

    public var title: String {
        switch self {
        case .unchanged: "Leave as-is"
        case .lower: "lowercase"
        case .upper: "UPPERCASE"
        case .start: "Start Case"
        case .sentence: "Sentence case"
        }
    }
}

public enum ArtistSeparator: String, Sendable, Codable, CaseIterable {
    case standard = "default"
    case mainOnly = "nothing"
    case andFeat = "andFeat"
    case ampersand = " & "
    case comma = ","
    case commaSpace = ", "
    case slash = "/"
    case spacedSlash = " / "
    case semicolon = ";"
    case semicolonSpace = "; "

    public var title: String {
        switch self {
        case .standard: "Standard multi-value tag"
        case .mainOnly: "Main artist only"
        case .andFeat: "Artist & Artist feat. Artist"
        default: "Joined with \"\(rawValue)\""
        }
    }
}

public struct TagSettings: Sendable, Codable, Equatable {
    public var title = true
    public var artist = true
    public var artists = true
    public var album = true
    public var cover = true
    public var trackNumber = true
    public var trackTotal = false
    public var discNumber = true
    public var discTotal = false
    public var albumArtist = true
    public var genre = true
    public var year = true
    public var date = true
    public var explicit = false
    public var isrc = true
    public var length = true
    public var barcode = true
    public var bpm = true
    public var replayGain = false
    public var label = true
    public var lyrics = false
    public var syncedLyrics = false
    public var copyright = false
    public var composer = false
    public var involvedPeople = false
    public var source = false
    public var rating = false
    public var savePlaylistAsCompilation = false
    public var useNullSeparator = false
    public var saveID3v1 = true
    public var multiArtistSeparator = ArtistSeparator.standard
    public var singleAlbumArtist = false
    public var coverDescriptionUTF8 = false
}

public struct DownloadSettings: Sendable, Codable, Equatable {
    public var downloadLocation = DownloadSettings.defaultMusicFolder

    public var tracknameTemplate = "%artist% - %title%"
    public var albumTracknameTemplate = "%tracknumber% - %title%"
    public var playlistTracknameTemplate = "%artist% - %title%"
    public var playlistNameTemplate = "%playlist%"
    public var artistNameTemplate = "%artist%"
    public var albumNameTemplate = "%artist% - %album%"
    public var playlistFilenameTemplate = "playlist"
    public var coverImageTemplate = "cover"
    public var artistImageTemplate = "folder"

    public var createPlaylistFolder = true
    public var createArtistFolder = false
    public var createAlbumFolder = true
    public var createCDFolder = true
    public var createStructurePlaylist = false
    public var createSingleFolder = false

    public var padTracks = true
    public var padSingleDigit = true
    public var paddingSize = 0
    public var illegalCharacterReplacer = "_"

    public var queueConcurrency = 8
    public var maxBitrate = TrackFormat.flac
    public var fallbackBitrate = true
    public var fallbackSearch = false
    public var fallbackISRC = false
    public var overwriteFile = OverwriteMode.skip
    public var logErrors = true
    public var logSearched = false
    public var createM3U8File = false
    public var syncedLyrics = false
    public var executeCommand = ""

    public var saveArtwork = true
    public var saveArtworkArtist = false
    public var embeddedArtworkSize = 800
    public var embeddedArtworkPNG = false
    public var localArtworkSize = 1200
    public var localArtworkFormat = "jpg"
    public var jpegImageQuality = 90
    public var finderArtwork = true

    public var dateFormat = "Y-M-D"
    public var albumVariousArtists = true
    public var removeAlbumVersion = false
    public var removeDuplicateArtists = true
    public var featuredToTitle = FeaturedTitleMode.unchanged
    public var titleCasing = TextCasing.unchanged
    public var artistCasing = TextCasing.unchanged

    public var tags = TagSettings()

    public init() {}

    public static let defaultMusicFolder = FileManager.default
        .urls(for: .musicDirectory, in: .userDomainMask).first?
        .appending(path: "deezdown Music").path(percentEncoded: false)
        ?? NSHomeDirectory() + "/Music/deezdown Music"

    public var localArtworkFormats: [ImageFormat] {
        localArtworkFormat.split(separator: ",").compactMap {
            switch $0.trimmingCharacters(in: .whitespaces).lowercased() {
            case "jpg", "jpeg": ImageFormat.jpeg(quality: jpegImageQuality)
            case "png": ImageFormat.png
            default: nil
            }
        }
    }

    public var embeddedArtworkFormat: ImageFormat {
        embeddedArtworkPNG ? .png : .jpeg(quality: jpegImageQuality)
    }

    /// Repairs values that would otherwise produce empty paths or nonsense output.
    public mutating func repair() {
        if downloadLocation.trimmingCharacters(in: .whitespaces).isEmpty {
            downloadLocation = Self.defaultMusicFolder
        }
        let defaults = DownloadSettings()
        let templates: [WritableKeyPath<Self, String>] = [
            \.tracknameTemplate, \.albumTracknameTemplate, \.playlistTracknameTemplate, \.playlistNameTemplate,
            \.artistNameTemplate, \.albumNameTemplate, \.playlistFilenameTemplate, \.coverImageTemplate,
            \.artistImageTemplate, \.dateFormat,
        ]
        for template in templates where self[keyPath: template].isEmpty {
            self[keyPath: template] = defaults[keyPath: template]
        }
        // An empty replacer deletes illegal characters; one that is itself illegal would make folders.
        illegalCharacterReplacer.removeAll { NameSanitizer.illegal.contains($0) }
        queueConcurrency = max(1, min(queueConcurrency, 16))
        paddingSize = max(0, min(paddingSize, 8))
        jpegImageQuality = max(1, min(jpegImageQuality, 100))
        embeddedArtworkSize = min(max(56, embeddedArtworkSize), Artwork.maximumSize)
        localArtworkSize = min(max(56, localArtworkSize), Artwork.maximumSize)
        if localArtworkFormats.isEmpty { localArtworkFormat = defaults.localArtworkFormat }
    }
}
