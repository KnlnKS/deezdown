import Foundation

extension DeezerSession {
    public func trackData(id: String) async throws -> JSONValue {
        if (Int(id) ?? 0) > 0 {
            let page = try await gateway("deezer.pageTrack", ["SNG_ID": .string(id)])
            if case .object(var data) = page["DATA"] {
                if page["LYRICS"] != .null { data["LYRICS"] = page["LYRICS"] }
                if page["ISRC"] != .null { data["ALBUM_FALLBACK"] = page["ISRC"] }
                return .object(data)
            }
        }
        return try await gateway("song.getData", ["SNG_ID": .string(id)])
    }

    public func trackList(ids: [String]) async throws -> [JSONValue] {
        guard !ids.isEmpty else { return [] }
        let results = try await gateway("song.getListData", ["SNG_IDS": .array(ids.map(JSONValue.string))])
        return results["data"].arrayValue
    }

    public func albumData(id: String) async throws -> JSONValue {
        try await gateway("album.getData", ["ALB_ID": .string(id)])
    }

    public func albumPage(id: String) async throws -> JSONValue {
        try await gateway("deezer.pageAlbum", ["ALB_ID": .string(id), "lang": "en", "header": true, "tab": 0])
    }

    public func albumTracks(id: String) async throws -> [JSONValue] {
        let results = try await gateway("song.getListByAlbum", ["ALB_ID": .string(id), "nb": -1])
        return results["data"].arrayValue
    }

    public func playlistPage(id: String) async throws -> JSONValue {
        try await gateway(
            "deezer.pagePlaylist",
            ["playlist_id": .string(id), "lang": "en", "header": true, "tab": 0, "nb": 0, "start": 0]
        )
    }

    public func playlistTracks(id: String) async throws -> [JSONValue] {
        let results = try await gateway("playlist.getSongs", ["playlist_id": .string(id), "nb": -1, "start": 0])
        return results["data"].arrayValue
    }

    public func artistData(id: String) async throws -> JSONValue {
        try await gateway("artist.getData", ["ART_ID": .string(id)])
    }

    public func artistPage(id: String) async throws -> JSONValue {
        try await gateway("deezer.pageArtist", ["ART_ID": .string(id), "lang": "en", "header": true, "tab": 0])
    }

    public func artistTopTracks(id: String) async throws -> [JSONValue] {
        let results = try await gateway("artist.getTopTrack", ["ART_ID": .string(id), "nb": 100])
        return results["data"].arrayValue
    }

    public func artistDiscography(id: String) async throws -> [JSONValue] {
        let pageSize = 100
        var albums: [JSONValue] = []
        var seen = Set<String>()
        var start = 0
        while true {
            let results = try await gateway(
                "album.getDiscography",
                [
                    "ART_ID": .string(id), "discography_mode": "all", "nb": .int(pageSize),
                    "nb_songs": 0, "start": .int(start),
                ]
            )
            let page = results["data"].arrayValue
            for album in page where seen.insert(album["ALB_ID"].stringValue ?? "").inserted {
                albums.append(album)
            }
            start += pageSize
            if page.isEmpty || start >= (results["total"].intValue ?? 0) { break }
        }
        return albums
    }

    public func lyrics(trackID: String) async throws -> JSONValue {
        try await gateway("song.getLyrics", ["SNG_ID": .string(trackID)])
    }

    public func search(query: String, kind: SearchKind, start: Int = 0, limit: Int) async throws -> (
        items: [JSONValue], total: Int
    ) {
        let results = try await gateway(
            "search.music",
            [
                "query": .string(query), "filter": "ALL", "output": .string(kind.rawValue.uppercased()),
                "start": .int(start), "nb": .int(limit),
            ]
        )
        return (results["data"].arrayValue, results["total"].intValue ?? 0)
    }

    public func searchAll(query: String, limit: Int) async throws -> JSONValue {
        try await gateway(
            "deezer.pageSearch",
            [
                "query": .string(query), "start": 0, "nb": .int(limit),
                "suggest": true, "artist_suggest": true, "top_tracks": true,
            ]
        )
    }

    public func profileTab(userID: String, tab: ProfileTab) async throws -> [JSONValue] {
        let results = try await gateway(
            "deezer.pageProfile", ["USER_ID": .string(userID), "tab": .string(tab.rawValue), "nb": 200]
        )
        return results["TAB"][tab.rawValue]["data"].arrayValue
    }

    /// The listening history behind Deezer's own "recently played" row.
    public func songsHistory() async throws -> [JSONValue] {
        let results = try await gateway("user.getSongsHistory", ["nb": 100, "start": 0])
        return results["data"].arrayValue
    }

    public func chartCountries() async throws -> [JSONValue] {
        let results = try await publicAPI("user/637006841/playlists", query: ["limit": "-1"])
        return results["data"].arrayValue.filter { ($0["title"].stringValue ?? "").hasPrefix("Top ") }
    }
}

public enum SearchKind: String, Sendable, CaseIterable {
    case track, album, artist, playlist

    public var title: String {
        switch self {
        case .track: "Tracks"
        case .album: "Albums"
        case .artist: "Artists"
        case .playlist: "Playlists"
        }
    }
}

public enum ProfileTab: String, Sendable {
    case playlists, albums, artists, loved
}

extension DeezerSession {
    /// Genres, UPC and record type only exist on the public API; one call covers a whole album,
    /// and none when the caller already has the album's public entry.
    public func enrichedAlbum(id: String, publicData known: JSONValue? = nil) async throws -> Album {
        async let publicTask = known == nil ? publicAPI("album/\(id)") : .null
        let gateway = try await albumData(id: id)
        let fetched = try? await publicTask
        return Album(gateway: gateway, publicData: known ?? fetched ?? .null)
    }

    /// BPM is per-track on the public API only, exactly as deemix fetches it.
    public func publicTrackBPM(id: String) async -> Double? {
        guard let results = try? await publicAPI("track/\(id)") else { return nil }
        let bpm = results["bpm"].doubleValue ?? 0
        return bpm > 0 ? bpm : nil
    }

    public func publicAlbum(upc: String) async throws -> JSONValue {
        if let direct = try? await publicAPI("album/upc:\(upc)"), direct["id"] != .null { return direct }
        let stripped = String(upc.drop { $0 == "0" })
        return try await publicAPI("album/upc:\(stripped)")
    }

    /// deemix's search fallback: progressively loosen the query until Deezer matches something.
    public func trackID(artist: String, title: String, album: String) async -> String? {
        var attempts: [String] = []
        if !album.isEmpty {
            attempts.append("artist:\"\(artist)\" track:\"\(title)\" album:\"\(album)\"")
        }
        attempts.append("artist:\"\(artist)\" track:\"\(title)\"")
        let stripped = title.replacingOccurrences(
            of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression
        )
        if stripped != title { attempts.append("artist:\"\(artist)\" track:\"\(stripped)\"") }
        if let dash = title.range(of: " - ") {
            attempts.append("artist:\"\(artist)\" track:\"\(title[title.startIndex..<dash.lowerBound])\"")
        }

        for query in attempts {
            guard let results = try? await publicAPI("search", query: ["q": query, "limit": "1"]),
                let id = results["data"][0]["id"].stringValue, id != "0"
            else { continue }
            return id
        }
        return nil
    }
}
