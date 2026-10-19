import Foundation

/// What deemix leaves beside a collection's tracks: the art of each album and artist folder it
/// fills, the playlist file, the logs and the post-download command. Gathered as the tracks
/// finish and written once the last one has.
struct CollectionExtras {
    var files: [URL?]
    var searched: [String] = []
    private(set) var failures: [String] = []
    /// Keyed by file path without extension, so each folder's art is saved once.
    private var albumArt: [URL: Artwork] = [:]
    private var artistArt: [URL: Artwork] = [:]

    init(trackCount: Int) {
        files = Array(repeating: nil, count: trackCount)
    }

    /// A line of deemix's errors.txt.
    mutating func fail(_ track: Track, _ message: String) {
        failures.append("\(track.id) | \(track.mainArtist.name) - \(track.title) | \(message)")
    }

    mutating func noteArtwork(
        for track: Track, at destination: DownloadPaths, context: DownloadContext, settings: DownloadSettings
    ) {
        let builder = PathBuilder(settings: settings)
        if settings.saveArtwork, let folder = destination.coverDirectory, !track.album.cover.isEmpty {
            let name = builder.collectionName(
                settings.coverImageTemplate, builder.albumVariables(track, context), fallback: "cover"
            )
            albumArt[folder.appending(path: name)] = track.album.cover
        }
        if settings.saveArtworkArtist, let folder = destination.artistDirectory,
            !track.album.mainArtist.picture.isEmpty
        {
            let name = builder.collectionName(
                settings.artistImageTemplate, builder.artistVariables(track, context), fallback: "folder"
            )
            artistArt[folder.appending(path: name)] = track.album.mainArtist.picture
        }
    }

    func write(
        for item: QueueItem, from collection: ResolvedCollection, context: DownloadContext,
        settings: DownloadSettings, artworkStore: ArtworkStore
    ) async {
        let builder = PathBuilder(settings: settings)
        guard let firstTrack = collection.tracks.first?.applying(settings) else { return }
        let extras = builder.paths(for: firstTrack, context: context).extrasDirectory

        var images = albumArt.flatMap { base, picture in
            settings.localArtworkFormats.map { (picture, $0, base) }
        }
        // Deezer has no PNG artist images.
        images += artistArt.map { base, picture in (picture, .jpeg(quality: settings.jpegImageQuality), base) }
        if settings.saveArtwork, !settings.tags.savePlaylistAsCompilation, let playlist = context.playlist,
            !playlist.picture.isEmpty
        {
            var cover = firstTrack
            cover.album.makePlaylistCompilation(playlist)
            let name = builder.collectionName(
                settings.coverImageTemplate, builder.albumVariables(cover, context), fallback: "cover"
            )
            images += settings.localArtworkFormats.map { (playlist.picture, $0, extras.appending(path: name)) }
        }
        await save(images, settings: settings, artworkStore: artworkStore)

        if settings.createM3U8File, !collection.isSingleTrack {
            let name = builder.collectionName(
                settings.playlistFilenameTemplate,
                builder.collectionVariables(item, playlist: collection.playlist, size: files.count),
                fallback: "playlist"
            )
            try? M3U8Writer.write(files: files, to: extras.appending(path: "\(name).m3u8"), relativeTo: extras)
        }

        // As in deemix, a collection rewrites its logs and runs the command on its folder; a
        // single track only adds its search, and names its file to the command.
        let command = settings.executeCommand
        if !collection.isSingleTrack {
            if settings.logErrors, !failures.isEmpty {
                try? LogWriter.write(failures, to: extras.appending(path: "errors.txt"))
            }
            if settings.logSearched, !searched.isEmpty {
                try? LogWriter.write(searched, to: extras.appending(path: "searched.txt"))
            }
            if !command.isEmpty { await PostCommand.run(command, folder: extras, filename: "") }
        } else if let file = files.first.flatMap({ $0 }) {
            if settings.logSearched, let line = searched.first {
                try? LogWriter.appendOnce(line, to: extras.appending(path: "searched.txt"))
            }
            if !command.isEmpty {
                await PostCommand.run(command, folder: extras, filename: M3U8Writer.relativePath(of: file, in: extras))
            }
        }
    }

    /// Fetches and writes every picture at once; one already on disk stays unless the
    /// overwrite mode rewrites existing files.
    private func save(_ images: [(Artwork, ImageFormat, URL)], settings: DownloadSettings, artworkStore: ArtworkStore)
        async
    {
        let replaces = [.overwrite, .tagsOnly, .keepBoth].contains(settings.overwriteFile)
        let size = settings.localArtworkSize
        await withTaskGroup { group in
            for (picture, format, base) in images {
                let file = base.appendingPathExtension(format.fileExtension)
                if !replaces, FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { continue }
                group.addTask {
                    guard let data = await artworkStore.image(picture, size: size, format: format) else { return }
                    try? data.write(to: file)
                }
            }
        }
    }
}
