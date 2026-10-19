import Foundation

public enum Tagger {
    static let involvedRoles = ["author", "engineer", "mixer", "producer", "writer"]

    /// Tagging rewrites the whole file, so it runs off the caller's actor.
    @concurrent
    public static func tag(
        _ track: Track,
        format: TrackFormat,
        at url: URL,
        artwork: Data?,
        settings: DownloadSettings
    ) async throws {
        switch format.fileExtension {
        case "mp3": try tagMP3(track, at: url, artwork: artwork, settings: settings)
        case "flac": try tagFLAC(track, at: url, artwork: artwork, settings: settings)
        default: break
        }
    }

    /// deemix's formula, kept at Python's two-decimal precision rather than the JS fork's.
    static func replayGain(_ gain: Double) -> String {
        String(format: "%.2f dB", (gain + 18.4) * -1)
    }

    /// deemix's ID3 writer joins several values with "/" (";" for genres), or with nulls when asked.
    static func joined(_ values: [String], _ tags: TagSettings, separator: String = "/") -> String {
        values.joined(separator: tags.useNullSeparator ? "\0" : separator)
    }

    /// The main artist alone, unless that is Various Artists and those are being left out.
    static func singleAlbumArtist(_ track: Track, _ settings: DownloadSettings) -> Bool {
        settings.tags.singleAlbumArtist
            && (!track.album.mainArtist.isVariousArtists || settings.albumVariousArtists)
    }

    // MARK: - MP3

    static func tagMP3(_ track: Track, at url: URL, artwork: Data?, settings: DownloadSettings) throws {
        let tags = settings.tags
        var writer = ID3v2Writer()

        if tags.title { writer.addText("TIT2", track.title) }
        if tags.artist {
            writer.addText(
                "TPE1", tags.multiArtistSeparator == .standard ? joined(track.artists, tags) : track.artistsString)
        }
        if tags.artists, tags.multiArtistSeparator != .standard {
            writer.addUserText("ARTISTS", joined(track.artists, tags))
        }
        if tags.album { writer.addText("TALB", track.album.title) }
        if tags.albumArtist {
            writer.addText(
                "TPE2",
                singleAlbumArtist(track, settings) ? track.album.mainArtist.name : joined(track.album.artists, tags)
            )
        }
        if tags.trackNumber {
            writer.addText(
                "TRCK",
                tags.trackTotal && track.album.trackTotal > 0
                    ? "\(track.trackNumber)/\(track.album.trackTotal)" : "\(track.trackNumber)"
            )
        }
        if tags.discNumber {
            writer.addText(
                "TPOS",
                tags.discTotal && track.album.discTotal > 0
                    ? "\(track.discNumber)/\(track.album.discTotal)" : "\(track.discNumber)"
            )
        }
        if tags.genre { writer.addText("TCON", joined(track.album.genres, tags, separator: ";")) }
        if let date = track.date ?? track.album.date {
            if tags.year { writer.addText("TYER", date.year) }
            if tags.date, date.day != "00", date.month != "00" {
                writer.addText("TDAT", "\(date.day)\(date.month)")
            }
        }
        if tags.length { writer.addText("TLEN", "\(track.duration * 1000)") }
        if tags.bpm, track.bpm > 0 { writer.addText("TBPM", "\(Int(track.bpm.rounded()))") }
        if tags.label { writer.addText("TPUB", track.album.label) }
        if tags.isrc { writer.addText("TSRC", track.isrc) }
        if tags.barcode { writer.addUserText("BARCODE", track.album.barcode) }
        if tags.explicit { writer.addUserText("ITUNESADVISORY", track.explicit ? "1" : "0") }
        if tags.replayGain, let gain = track.gain {
            writer.addUserText("REPLAYGAIN_TRACK_GAIN", replayGain(gain))
        }
        if tags.lyrics, let unsynced = track.lyrics?.unsynced { writer.addUnsyncedLyrics(unsynced) }
        if tags.syncedLyrics, let lyrics = track.lyrics { writer.addSyncedLyrics(lyrics.id3Sync) }
        if tags.composer { writer.addText("TCOM", joined(track.contributors["composer"] ?? [], tags)) }
        if tags.involvedPeople {
            var pairs: [(role: String, person: String)] = []
            for role in involvedRoles {
                for person in track.contributors[role] ?? [] { pairs.append((role, person)) }
            }
            writer.addInvolvedPeople(pairs)
        }
        if tags.copyright { writer.addText("TCOP", track.copyright) }
        if track.album.recordType == .compile { writer.addText("TCMP", "1") }
        if tags.source {
            writer.addUserText("SOURCE", "Deezer")
            writer.addUserText("SOURCEID", track.id)
        }
        if tags.rating {
            writer.addPopularimeter(rating: UInt8(min(255, (Double(track.rank) / 10000 * 2.55).rounded())))
        }
        if let artwork { writer.addPicture(artwork, useUnicode: tags.coverDescriptionUTF8) }

        var trailer = Data()
        if tags.saveID3v1 {
            trailer = ID3v1Writer.tag(
                title: track.title,
                artist: track.artistsString.isEmpty ? track.mainArtist.name : track.artistsString,
                album: track.album.title,
                year: (track.date ?? track.album.date)?.year ?? "",
                trackNumber: track.trackNumber,
                genre: track.album.genres.first
            )
        }

        try rewrite(url, prefix: writer.data(), suffix: trailer)
    }

    /// Replaces any existing ID3v1/ID3v2 wrapper.
    static func rewrite(_ url: URL, prefix: Data, suffix: Data) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }

        var audioStart: UInt64 = 0
        if let header = try handle.read(upToCount: 10), header.starts(with: Array("ID3".utf8)) {
            audioStart = UInt64(10 + ID3v2Writer.synchsafeValue(Array(header[6..<10])))
        }

        let totalSize = try handle.seekToEnd()
        var audioEnd = totalSize
        if totalSize > 128 {
            try handle.seek(toOffset: totalSize - 128)
            if let tail = try handle.read(upToCount: 3), tail == Data("TAG".utf8) {
                audioEnd = totalSize - 128
            }
        }

        try TagRewriter.rewrite(
            url, reading: handle, header: prefix,
            audioFrom: audioStart, audioTo: audioEnd, trailer: suffix
        )
    }

    // MARK: - FLAC

    static func tagFLAC(_ track: Track, at url: URL, artwork: Data?, settings: DownloadSettings) throws {
        let tags = settings.tags
        var comments: [(String, String)] = []
        func add(_ field: String, _ value: String) {
            guard !value.isEmpty else { return }
            comments.append((field, value))
        }

        if tags.title { add("TITLE", track.title) }
        if tags.artist {
            if tags.multiArtistSeparator == .standard {
                for artist in track.artists { add("ARTIST", artist) }
            } else {
                add("ARTIST", track.artistsString)
            }
        }
        if tags.artists, tags.multiArtistSeparator != .standard {
            for artist in track.artists { add("ARTISTS", artist) }
        }
        if tags.album { add("ALBUM", track.album.title) }
        if tags.albumArtist {
            if singleAlbumArtist(track, settings) {
                add("ALBUMARTIST", track.album.mainArtist.name)
            } else {
                for artist in track.album.artists { add("ALBUMARTIST", artist) }
            }
        }
        if tags.trackNumber { add("TRACKNUMBER", "\(track.trackNumber)") }
        if tags.trackTotal, track.album.trackTotal > 0 { add("TRACKTOTAL", "\(track.album.trackTotal)") }
        if tags.discNumber { add("DISCNUMBER", "\(track.discNumber)") }
        if tags.discTotal, track.album.discTotal > 0 { add("DISCTOTAL", "\(track.album.discTotal)") }
        if tags.genre { for genre in track.album.genres { add("GENRE", genre) } }
        if tags.date, let date = track.date?.formatted(settings.dateFormat), !date.isEmpty {
            add("DATE", date)
        } else if tags.year, let year = (track.date ?? track.album.date)?.year {
            add("DATE", year)
        }
        if tags.length { add("LENGTH", "\(track.duration * 1000)") }
        if tags.bpm, track.bpm > 0 { add("BPM", "\(Int(track.bpm.rounded()))") }
        if tags.label { add("PUBLISHER", track.album.label) }
        if tags.isrc { add("ISRC", track.isrc) }
        if tags.barcode { add("BARCODE", track.album.barcode) }
        if tags.explicit { add("ITUNESADVISORY", track.explicit ? "1" : "0") }
        if tags.replayGain, let gain = track.gain { add("REPLAYGAIN_TRACK_GAIN", replayGain(gain)) }
        if tags.lyrics, let unsynced = track.lyrics?.unsynced { add("LYRICS", unsynced) }
        if tags.involvedPeople {
            for role in involvedRoles {
                for person in track.contributors[role] ?? [] { add(role.uppercased(), person) }
            }
            for publisher in track.contributors["musicpublisher"] ?? [] { add("ORGANIZATION", publisher) }
        }
        if tags.composer { for composer in track.contributors["composer"] ?? [] { add("COMPOSER", composer) } }
        if tags.copyright { add("COPYRIGHT", track.copyright) }
        if track.album.recordType == .compile { add("COMPILATION", "1") }
        if tags.source {
            add("SOURCE", "Deezer")
            add("SOURCEID", track.id)
        }
        if tags.rating { add("RATING", "\(Int((Double(track.rank) / 10000).rounded()))") }

        try FLACTagWriter.write(comments: comments, picture: artwork, to: url)
    }
}
