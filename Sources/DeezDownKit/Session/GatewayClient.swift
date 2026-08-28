import Foundation

extension DeezerSession {
    public func trackData(id: String) async throws -> JSONValue {
        guard let numeric = Int(id), numeric > 0 else {
            return try await gateway("song.getData", ["SNG_ID": .string(id)])
        }
        let page = try await gateway("deezer.pageTrack", ["SNG_ID": .string(id)])
        guard case .object(var data) = page["DATA"] else {
            return try await gateway("song.getData", ["SNG_ID": .string(id)])
        }
        if page["LYRICS"] != .null { data["LYRICS"] = page["LYRICS"] }
        if page["ISRC"] != .null { data["ALBUM_FALLBACK"] = page["ISRC"] }
        return .object(data)
    }

    public func trackList(ids: [String]) async throws -> [JSONValue] {
        guard !ids.isEmpty else { return [] }
        let results = try await gateway("song.getListData", ["SNG_IDS": .array(ids.map(JSONValue.string))])
        return results["data"].arrayValue
    }

    public func refreshedTrackToken(id: String) async throws -> (token: String, expires: Int) {
        let results = try await gateway(
            "song.getData",
            ["SNG_ID": .string(id), "array_default": .array(["TRACK_TOKEN", "TRACK_TOKEN_EXPIRE"])]
        )
        guard let token = results["TRACK_TOKEN"].stringValue else { throw DeezerError.badResponse }
        return (token, results["TRACK_TOKEN_EXPIRE"].intValue ?? 0)
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

    public func artistTopTracks(id: String, limit: Int = 100) async throws -> [JSONValue] {
        let results = try await gateway("artist.getTopTrack", ["ART_ID": .string(id), "nb": .int(limit)])
        return results["data"].arrayValue
    }

    public func artistDiscography(id: String, pageSize: Int = 100) async throws -> [JSONValue] {
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

    public func search(query: String, kind: SearchKind, start: Int = 0, limit: Int = 40) async throws -> (
        items: [JSONValue], total: Int
    ) {
        let results = try await gateway(
            "search.music",
            [
                "query": .string(query), "filter": "ALL", "output": .string(kind.gatewayOutput),
                "start": .int(start), "nb": .int(limit),
            ]
        )
        return (results["data"].arrayValue, results["total"].intValue ?? 0)
    }

    public func searchAll(query: String, limit: Int = 10) async throws -> JSONValue {
        try await gateway(
            "deezer.pageSearch",
            [
                "query": .string(query), "start": 0, "nb": .int(limit),
                "suggest": true, "artist_suggest": true, "top_tracks": true,
            ]
        )
    }

    public func favoriteTrackIDs() async throws -> [String] {
        let results = try await gateway("song.getFavoriteIds", ["nb": 10000, "start": 0, "checksum": .null])
        return results["data"].arrayValue.compactMap { $0["SNG_ID"].stringValue }
    }

    public func profileTab(userID: String, tab: ProfileTab, limit: Int = 200) async throws -> [JSONValue] {
        let results = try await gateway(
            "deezer.pageProfile",
            ["USER_ID": .string(userID), "tab": .string(tab.rawValue), "nb": .int(limit)]
        )
        return results["TAB"][tab.rawValue]["data"].arrayValue
    }

    public func userMenu() async throws -> JSONValue {
        try await gateway("deezer.userMenu")
    }

    public func chartCountries() async throws -> [JSONValue] {
        let results = try await publicAPI("user/637006841/playlists", query: ["limit": "-1"])
        return results["data"].arrayValue.filter { ($0["title"].stringValue ?? "").hasPrefix("Top ") }
    }
}

public enum SearchKind: String, Sendable, CaseIterable, Identifiable {
    case track, album, artist, playlist

    public var id: String { rawValue }

    var gatewayOutput: String {
        switch self {
        case .track: "TRACK"
        case .album: "ALBUM"
        case .artist: "ARTIST"
        case .playlist: "PLAYLIST"
        }
    }

    public var title: String {
        switch self {
        case .track: "Tracks"
        case .album: "Albums"
        case .artist: "Artists"
        case .playlist: "Playlists"
        }
    }
}

public enum ProfileTab: String, Sendable, CaseIterable {
    case playlists, albums, artists, loved
}

extension DeezerSession {
    /// Genres, UPC and record type only exist on the public API; one call covers a whole album.
    public func enrichedAlbum(id: String) async throws -> Album {
        let gateway = try await albumData(id: id)
        let publicData = try? await publicAPI("album/\(id)")
        return Album(gateway: gateway, publicData: publicData ?? .null)
    }

    /// BPM is per-track on the public API only, exactly as deemix fetches it.
    public func publicTrackBPM(id: String) async -> Double? {
        guard let results = try? await publicAPI("track/\(id)") else { return nil }
        let bpm = results["bpm"].doubleValue ?? 0
        return bpm > 0 ? bpm : nil
    }

    public func publicTrack(isrc: String) async throws -> JSONValue {
        try await publicAPI("track/isrc:\(isrc)")
    }

    public func publicAlbum(upc: String) async throws -> JSONValue {
        if let direct = try? await publicAPI("album/upc:\(upc)"), direct["id"] != .null { return direct }
        let stripped = String(upc.drop { $0 == "0" })
        return try await publicAPI("album/upc:\(stripped)")
    }

    /// deemix's search fallback: progressively loosen the query until Deezer matches something.
    public func trackID(artist: String, title: String, album: String?) async -> String? {
        var attempts: [String] = []
        if let album, !album.isEmpty {
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
