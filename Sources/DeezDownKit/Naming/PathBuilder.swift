import Foundation

struct DownloadContext: Sendable {
    var playlist: Playlist?
    var isSingleTrackDownload = false
    var rootArtist: ArtistRef?
    var format = TrackFormat.flac
    var today = CustomDate.today
}

struct DownloadPaths: Sendable, Equatable {
    var filename: String
    var directory: URL
    var artistDirectory: URL?
    var coverDirectory: URL?
    var extrasDirectory: URL
}

public struct PathBuilder: Sendable {
    let settings: DownloadSettings

    init(settings: DownloadSettings) {
        self.settings = settings
    }

    func trackVariables(_ track: Track, _ context: DownloadContext) -> TemplateVariables {
        let date = track.date ?? track.album.date
        let featured = track.featuredArtistsString
        return [
            "title": track.title,
            "artist": track.mainArtist.name,
            "artists": track.artists.joined(separator: ", "),
            "tagsartists": track.artistsString,
            "allartists": track.fullArtistsString,
            "mainartists": track.mainArtistsString,
            "featartists": featured.isEmpty ? "" : "(\(featured))",
            "album": track.album.title,
            "albumartist": track.album.mainArtist.name,
            "tracknumber": NameSanitizer.pad(track.trackNumber, total: track.album.trackTotal, settings: settings),
            "tracktotal": String(track.album.trackTotal),
            "discnumber": String(track.discNumber),
            "disctotal": String(track.album.discTotal),
            "genre": track.album.genres.first ?? "Unknown",
            "year": date?.year ?? "",
            "date": track.date?.formatted(settings.dateFormat) ?? "",
            "bpm": track.bpm > 0 ? String(Int(track.bpm.rounded())) : "",
            "label": track.album.label,
            "isrc": track.isrc,
            "upc": track.album.barcode,
            "explicit": track.explicit ? "(Explicit)" : "",
            "track_id": track.id,
            "album_id": track.album.id,
            "artist_id": track.mainArtist.id,
            "playlist_id": context.playlist?.id ?? "",
            "position": NameSanitizer.pad(
                context.playlist != nil ? (track.position ?? track.trackNumber) : track.trackNumber,
                total: context.playlist?.trackCount ?? track.album.trackTotal,
                settings: settings
            ),
        ]
    }

    func albumVariables(_ track: Track, _ context: DownloadContext) -> TemplateVariables {
        let album = track.album
        return [
            "album": album.title,
            "album_id": album.id,
            "genre": album.isPlaylistCompilation ? "Compile" : (album.genres.first ?? "Unknown"),
            "artist": album.mainArtist.name,
            "artists": album.artists.joined(separator: ", "),
            "artist_id": album.mainArtist.id,
            "root_artist": context.rootArtist?.name ?? album.mainArtist.name,
            "root_artist_id": context.rootArtist?.id ?? album.mainArtist.id,
            "playlist": context.playlist?.title ?? "",
            "tracktotal": String(album.trackTotal),
            "disctotal": String(album.discTotal),
            "type": album.recordType.rawValue.prefix(1).uppercased() + album.recordType.rawValue.dropFirst(),
            "upc": album.barcode,
            "explicit": album.explicit ? "(Explicit)" : "",
            "label": album.label,
            "year": album.date?.year ?? "",
            "date": album.date?.formatted(settings.dateFormat) ?? "",
            "bitrate": context.format.displayName,
        ]
    }

    func artistVariables(_ track: Track, _ context: DownloadContext) -> TemplateVariables {
        [
            "artist": track.album.mainArtist.name,
            "artist_id": track.album.mainArtist.id,
            "root_artist": context.rootArtist?.name ?? track.album.mainArtist.name,
            "root_artist_id": context.rootArtist?.id ?? track.album.mainArtist.id,
        ]
    }

    func playlistVariables(_ playlist: Playlist, _ context: DownloadContext) -> TemplateVariables {
        [
            "playlist": playlist.title,
            "playlist_id": playlist.id,
            "owner": playlist.owner,
            "owner_id": playlist.ownerID,
            "year": playlist.date?.year ?? "",
            "date": playlist.date?.formatted(settings.dateFormat) ?? "",
            "explicit": playlist.explicit ? "(Explicit)" : "",
            "today": context.today.formatted(settings.dateFormat),
        ]
    }

    func paths(for track: Track, context: DownloadContext) -> DownloadPaths {
        let asCompilation = settings.tags.savePlaylistAsCompilation && context.playlist != nil
        let insidePlaylist = context.playlist != nil && !asCompilation
        let followsAlbumStructure = !insidePlaylist || settings.createStructurePlaylist

        var directory = URL(fileURLWithPath: settings.downloadLocation, isDirectory: true)

        if insidePlaylist, settings.createPlaylistFolder, let playlist = context.playlist {
            directory = nest(directory, settings.playlistNameTemplate, playlistVariables(playlist, context))
        }
        let playlistDirectory = insidePlaylist ? directory : nil

        var artistDirectory: URL?
        if followsAlbumStructure, settings.createArtistFolder {
            directory = nest(directory, settings.artistNameTemplate, artistVariables(track, context))
            artistDirectory = directory
        }

        let wantsAlbumFolder =
            followsAlbumStructure && settings.createAlbumFolder
            && (!context.isSingleTrackDownload || settings.createSingleFolder)
        var coverDirectory: URL?
        if wantsAlbumFolder {
            directory = nest(directory, settings.albumNameTemplate, albumVariables(track, context))
            coverDirectory = directory
        }
        let extrasDirectory = playlistDirectory ?? directory

        if wantsAlbumFolder, settings.createCDFolder, track.album.discTotal > 1 {
            directory = directory.appending(path: "CD\(track.discNumber)")
        }

        var parts = components(filenameTemplate(for: context), trackVariables(track, context))
        let filename = parts.removeLast()

        return DownloadPaths(
            filename: filename,
            directory: parts.reduce(directory) { $0.appending(path: $1) },
            artistDirectory: artistDirectory,
            coverDirectory: coverDirectory,
            extrasDirectory: extrasDirectory
        )
    }

    /// As in deemix, the template follows what was asked for: a playlist, even one saved as a
    /// compilation, names its tracks with the playlist template.
    func filenameTemplate(for context: DownloadContext) -> String {
        if context.playlist != nil {
            settings.playlistTracknameTemplate
        } else if context.isSingleTrackDownload && !settings.createSingleFolder {
            settings.tracknameTemplate
        } else {
            settings.albumTracknameTemplate
        }
    }

    func collectionVariables(_ item: QueueItem, playlist: Playlist?, size: Int) -> TemplateVariables {
        [
            "title": item.title,
            "artist": item.subtitle,
            "size": String(size),
            "type": item.link.kind,
            "id": item.link.identifier,
            "playlist": playlist?.title ?? "",
            "bitrate": item.format.displayName,
        ]
    }

    /// Cover, artist image and playlist file names stay a single component.
    func collectionName(_ template: String, _ variables: TemplateVariables, fallback: String) -> String {
        let name = components(template, variables).joined(separator: settings.illegalCharacterReplacer)
        return name == "dot" ? fallback : name
    }

    private func nest(_ directory: URL, _ template: String, _ variables: TemplateVariables) -> URL {
        components(template, variables).reduce(directory) { $0.appending(path: $1) }
    }

    /// Values are made safe before they go in, so only a slash in the template itself makes a
    /// folder, as in deemix.
    private func components(_ template: String, _ variables: TemplateVariables) -> [String] {
        let replacer = settings.illegalCharacterReplacer
        let rendered = TemplateEngine.render(template, variables) { NameSanitizer.fixName($0, replacer: replacer) }
        let parts = rendered.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map {
            NameSanitizer.component($0.trimmingCharacters(in: .whitespaces), replacer: replacer)
        }
        return parts.isEmpty ? ["dot"] : parts
    }
}

/// The placeholders each template can use, read off the variables a download fills in, so
/// Settings can't offer one that would render as itself.
extension PathBuilder {
    private static let blank = (
        builder: PathBuilder(settings: DownloadSettings()), track: Track(gateway: .null), context: DownloadContext()
    )

    public static let trackTokens = blank.builder.trackVariables(blank.track, blank.context).map(\.key)
    public static let albumTokens = blank.builder.albumVariables(blank.track, blank.context).map(\.key)
    public static let artistTokens = blank.builder.artistVariables(blank.track, blank.context).map(\.key)
    public static let playlistTokens = blank.builder.playlistVariables(Playlist(gateway: .null), blank.context)
        .map(\.key)
    public static let collectionTokens = blank.builder.collectionVariables(
        QueueItem(link: .track(""), title: "", subtitle: "", cover: Artwork(md5: "", kind: .cover), format: .flac),
        playlist: nil, size: 0
    ).map(\.key)
}
