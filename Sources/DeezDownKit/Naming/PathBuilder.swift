import Foundation

public struct DownloadContext: Sendable {
    public var playlist: Playlist?
    public var isSingleTrackDownload: Bool
    public var rootArtist: ArtistRef?
    public var format: TrackFormat
    public var today: CustomDate

    public init(
        playlist: Playlist? = nil,
        isSingleTrackDownload: Bool = false,
        rootArtist: ArtistRef? = nil,
        format: TrackFormat = .flac,
        today: CustomDate = CustomDate(deezerString: ISO8601DateFormatter().string(from: Date())) ?? CustomDate()
    ) {
        self.playlist = playlist
        self.isSingleTrackDownload = isSingleTrackDownload
        self.rootArtist = rootArtist
        self.format = format
        self.today = today
    }
}

public struct DownloadPaths: Sendable, Equatable {
    public var filename: String
    public var directory: URL
    public var artistDirectory: URL?
    public var coverDirectory: URL
    public var extrasDirectory: URL

    public func file(extension fileExtension: String) -> URL {
        directory.appending(path: "\(filename).\(fileExtension)")
    }
}

public struct PathBuilder: Sendable {
    let settings: DownloadSettings

    public init(settings: DownloadSettings) {
        self.settings = settings
    }

    public func trackVariables(_ track: Track, _ context: DownloadContext) -> [String: String] {
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
            "date": track.dateString,
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

    public func albumVariables(_ track: Track, _ context: DownloadContext) -> [String: String] {
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
            "type": album.recordType.displayName,
            "upc": album.barcode,
            "explicit": album.explicit ? "(Explicit)" : "",
            "label": album.label,
            "year": album.date?.year ?? "",
            "date": album.dateString,
            "bitrate": context.format.displayName,
        ]
    }

    public func artistVariables(_ track: Track, _ context: DownloadContext) -> [String: String] {
        [
            "artist": track.album.mainArtist.name,
            "artist_id": track.album.mainArtist.id,
            "root_artist": context.rootArtist?.name ?? track.album.mainArtist.name,
            "root_artist_id": context.rootArtist?.id ?? track.album.mainArtist.id,
        ]
    }

    public func playlistVariables(_ playlist: Playlist, _ context: DownloadContext) -> [String: String] {
        [
            "playlist": playlist.title,
            "playlist_id": playlist.id,
            "owner": playlist.owner,
            "owner_id": playlist.ownerID,
            "year": playlist.date?.year ?? "",
            "date": playlist.date?.formatted(settings.dateFormat.rawValue) ?? "",
            "explicit": playlist.explicit ? "(Explicit)" : "",
            "today": context.today.formatted(settings.dateFormat.rawValue),
        ]
    }

    public func paths(for track: Track, context: DownloadContext) -> DownloadPaths {
        let asCompilation = settings.tags.savePlaylistAsCompilation && context.playlist != nil
        let insidePlaylist = context.playlist != nil && !asCompilation
        let followsAlbumStructure = !insidePlaylist || settings.createStructurePlaylist

        var directory = URL(fileURLWithPath: settings.downloadLocation, isDirectory: true)

        if insidePlaylist, settings.createPlaylistFolder, let playlist = context.playlist {
            directory = directory.appending(
                path: component(settings.playlistNameTemplate, playlistVariables(playlist, context))
            )
        }
        var extrasDirectory: URL? = insidePlaylist ? directory : nil

        var artistDirectory: URL?
        if followsAlbumStructure, settings.createArtistFolder {
            directory = directory.appending(
                path: component(settings.artistNameTemplate, artistVariables(track, context))
            )
            artistDirectory = directory
        }

        let wantsAlbumFolder =
            followsAlbumStructure && settings.createAlbumFolder
            && (!context.isSingleTrackDownload || settings.createSingleFolder)
        var coverDirectory: URL?
        if wantsAlbumFolder {
            directory = directory.appending(
                path: component(settings.albumNameTemplate, albumVariables(track, context))
            )
            coverDirectory = directory
        }

        let extras = extrasDirectory ?? directory
        extrasDirectory = extras

        if wantsAlbumFolder, settings.createCDFolder, track.album.discTotal > 1 {
            directory = directory.appending(path: "CD\(track.discNumber)")
        }

        let template =
            if insidePlaylist {
                settings.playlistTracknameTemplate
            } else if context.isSingleTrackDownload && !settings.createSingleFolder {
                settings.tracknameTemplate
            } else {
                settings.albumTracknameTemplate
            }

        var rendered = TemplateEngine.render(template, trackVariables(track, context))
        rendered = NameSanitizer.fixName(rendered, replacer: settings.illegalCharacterReplacer)
        rendered = NameSanitizer.fixLongName(rendered)

        // A separator that survives sanitization becomes a real subfolder, as in deemix.
        if let slash = rendered.firstIndex(of: "/") {
            directory = directory.appending(path: NameSanitizer.antiDot(String(rendered[..<slash])))
            rendered = String(rendered[rendered.index(after: slash)...])
        }

        return DownloadPaths(
            filename: NameSanitizer.antiDot(rendered),
            directory: directory,
            artistDirectory: artistDirectory,
            coverDirectory: coverDirectory ?? extras,
            extrasDirectory: extras
        )
    }

    /// Collection filenames must stay a single component, so a rendered slash is replaced.
    public func collectionName(_ template: String, _ variables: [String: String], fallback: String) -> String {
        let rendered = TemplateEngine.render(template, variables)
            .replacingOccurrences(of: "/", with: settings.illegalCharacterReplacer)
        let cleaned = NameSanitizer.component(rendered, replacer: settings.illegalCharacterReplacer)
        return cleaned == "dot" || cleaned.isEmpty ? fallback : cleaned
    }

    private func component(_ template: String, _ variables: [String: String]) -> String {
        let rendered = TemplateEngine.render(template, variables)
        let cleaned = NameSanitizer.component(rendered, replacer: settings.illegalCharacterReplacer)
        return cleaned.isEmpty ? "Unknown" : cleaned
    }
}
