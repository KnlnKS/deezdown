import Foundation

public struct ResolvedMedia: Sendable {
    public var track: Track
    public var format: TrackFormat
    public var urls: [URL]
}

/// Turns tracks into downloadable CDN URLs, batching Deezer's `get_url` up to its 100-token
/// ceiling and walking the quality ladder a whole tier at a time rather than a track at a time.
public struct MediaResolver: Sendable {
    public static let batchLimit = 100

    private let session: DeezerSession
    private let settings: DownloadSettings

    public init(session: DeezerSession, settings: DownloadSettings) {
        self.session = session
        self.settings = settings
    }

    /// deemix's order: the preferred family from the requested quality down, then its
    /// catch-all MP3 for anything that offers one.
    public func ladder(for preferred: TrackFormat) -> [TrackFormat] {
        guard settings.fallbackBitrate else { return [preferred] }
        if preferred.isSpatial { return [.mp4ra3, .mp4ra2, .mp4ra1].filter { $0 <= preferred } }
        return [.flac, .mp3_320, .mp3_128].filter { $0 <= preferred } + [.default]
    }

    public func resolve(_ tracks: [Track], format preferred: TrackFormat) async throws
        -> [Result<ResolvedMedia, DownloadFailure>]
    {
        let pending = try await refreshingExpiredTokens(tracks)
        var (outcomes, lastReason) = try await streams(for: pending, format: preferred)

        // As in deemix, a track that fails for any reason, including not being encoded yet,
        // tries Deezer's replacement, then the same ISRC elsewhere, then a search.
        var alternatives = [fallbackReplacements]
        if settings.fallbackISRC { alternatives.append(isrcReplacements) }
        if settings.fallbackSearch { alternatives.append(searchReplacements) }
        for standIns in alternatives {
            let unresolved = pending.indices.filter { outcomes[$0] == nil }
            guard !unresolved.isEmpty else { break }
            let found = await standIns(unresolved.map { pending[$0] })
            try await adopt(
                zip(unresolved, found).compactMap { index, standIn in standIn.map { (index, $0) } },
                for: pending, into: &outcomes, format: preferred
            )
        }

        // As in deemix, a 360 request that found no 360 file at any level has no 360 version.
        let noSpatialVersion = preferred.isSpatial && settings.fallbackBitrate
        return outcomes.indices.map { index in
            let reason = lastReason[index] ?? .notAvailable
            return outcomes[index].map(Result.success)
                ?? .failure(
                    DownloadFailure(
                        noSpatialVersion && reason == .wrongBitrate ? .notSpatial : reason,
                        exhaustedAlternatives: true
                    ))
        }
    }

    /// Walks the ladder for every track at once; local uploads only ever have their own MP3.
    private func streams(for tracks: [Track], format preferred: TrackFormat) async throws
        -> ([ResolvedMedia?], [Int: DownloadFailure.Reason])
    {
        guard let user = await session.user else { throw DeezerError.notLoggedIn }
        var outcomes = [ResolvedMedia?](repeating: nil, count: tracks.count)
        var lastReason: [Int: DownloadFailure.Reason] = [:]
        for (index, track) in tracks.enumerated() where !track.isEncoded && !track.isLocal {
            lastReason[index] = .notEncoded
        }

        for format in [.local] + ladder(for: preferred) {
            let unresolved = tracks.indices.filter {
                outcomes[$0] == nil && lastReason[$0] != .notEncoded && tracks[$0].isLocal == (format == .local)
            }
            guard !unresolved.isEmpty else { continue }
            guard user.canStream(format) else {
                for index in unresolved { lastReason[index] = .wrongLicense }
                continue
            }

            let candidates = unresolved.filter { tracks[$0].filesize(for: format) > 0 }
            for index in unresolved where tracks[index].filesize(for: format) == 0 {
                lastReason[index] = lastReason[index] ?? .wrongBitrate
            }
            let answers = try await candidates.batches(of: Self.batchLimit) { [session] batch in
                try await session.trackURLs(trackTokens: batch.map { tracks[$0].trackToken }, format: format)
            }
            for (batch, media) in answers {
                for (index, result) in zip(batch, media) {
                    switch result {
                    case .success(let primary, let mirrors):
                        outcomes[index] = ResolvedMedia(track: tracks[index], format: format, urls: [primary] + mirrors)
                    case .failure(let code, _):
                        lastReason[index] = code == 2002 ? .wrongGeolocation(user.country) : .notAvailable
                    }
                }
            }
        }
        return (outcomes, lastReason)
    }

    /// Resolves stand-ins for the tracks that failed, and, as deemix's retries do, Deezer's
    /// replacement for any stand-in that fails too, down its chain. A stand-in only lends its
    /// stream, as deemix's parseEssentialData does: the tags still describe the track that was
    /// asked for.
    private func adopt(
        _ standIns: [(Int, Track)], for originals: [Track], into outcomes: inout [ResolvedMedia?],
        format preferred: TrackFormat
    ) async throws {
        var standIns = standIns
        var tried: [Int: Set<String>] = [:]
        while !standIns.isEmpty {
            for (index, standIn) in standIns { tried[index, default: [originals[index].id]].insert(standIn.id) }
            let (resolved, _) = try await streams(for: standIns.map(\.1), format: preferred)
            var failed: [(Int, Track)] = []
            for ((index, standIn), found) in zip(standIns, resolved) {
                if var media = found {
                    media.track = originals[index].streaming(from: media.track)
                    outcomes[index] = media
                } else {
                    failed.append((index, standIn))
                }
            }
            // A chain that leads back to a track already tried ends there.
            standIns = zip(failed, await fallbackReplacements(failed.map(\.1))).compactMap { failure, next in
                guard let next, tried[failure.0]?.contains(next.id) == false else { return nil }
                return (failure.0, next)
            }
        }
    }

    /// Deezer publishes replacement IDs for dead tracks.
    private func fallbackReplacements(_ tracks: [Track]) async -> [Track?] {
        let answers = try? await tracks.compactMap(\.fallbackID).batches(of: Self.batchLimit) { [session] batch in
            (try? await session.trackList(ids: batch)) ?? []
        }
        let found = Dictionary((answers ?? []).flatMap(\.1).map { Track(gateway: $0) }.map { ($0.id, $0) }) { $1 }
        return tracks.map { $0.fallbackID.flatMap { found[$0] } }
    }

    /// The same recording often exists on other releases; try those before giving up. Each
    /// round reads every waiting track's next release at once, and a release several tracks
    /// share is read once.
    private func isrcReplacements(_ tracks: [Track]) async -> [Track?] {
        var releases = await tracks.concurrentMap { [session] track -> [String] in
            guard !track.isrc.isEmpty else { return [] }
            var albumIDs = track.alternativeAlbumIDs
            if albumIDs.isEmpty, let refreshed = try? await session.trackData(id: track.id) {
                albumIDs = Track(gateway: refreshed).alternativeAlbumIDs
            }
            return albumIDs.filter { $0 != track.album.id }
        }
        var tracklists: [String: [JSONValue]] = [:]
        var found = [Track?](repeating: nil, count: tracks.count)
        while true {
            let waiting = tracks.indices.filter { !releases[$0].isEmpty }
            guard !waiting.isEmpty else { break }
            let next = waiting.map { releases[$0].removeFirst() }
            let unread = Array(Set(next).subtracting(tracklists.keys))
            let read = await unread.concurrentMap { [session] in (try? await session.albumTracks(id: $0)) ?? [] }
            tracklists.merge(zip(unread, read)) { $1 }
            for (index, albumID) in zip(waiting, next) {
                guard let match = tracklists[albumID]?.first(where: { $0["ISRC"].stringValue == tracks[index].isrc }),
                    match["SNG_ID"].stringValue != tracks[index].id
                else { continue }
                found[index] = Track(gateway: match)
                releases[index] = []
            }
        }
        return found
    }

    /// Last resort: ask Deezer to find the same song by its metadata.
    private func searchReplacements(_ tracks: [Track]) async -> [Track?] {
        await tracks.concurrentMap { [session] track in
            guard
                let foundID = await session.trackID(
                    artist: track.mainArtist.name, title: track.title, album: track.album.title
                ),
                foundID != track.id,
                let entry = try? await session.trackData(id: foundID)
            else { return nil }
            var candidate = Track(gateway: entry)
            candidate.searched = true
            return candidate
        }
    }

    private func refreshingExpiredTokens(_ tracks: [Track]) async throws -> [Track] {
        var tracks = tracks
        let stale = tracks.indices.filter { tracks[$0].trackToken.isEmpty || tracks[$0].tokenIsExpired }
        guard !stale.isEmpty else { return tracks }

        var fresh: [String: (token: String, expires: Int)] = [:]
        let answers = try await stale.map { tracks[$0].id }.batches(of: Self.batchLimit) { [session] batch in
            try await session.trackList(ids: batch)
        }
        for entry in answers.flatMap(\.1) {
            guard let id = entry["SNG_ID"].stringValue, let token = entry["TRACK_TOKEN"].stringValue else { continue }
            fresh[id] = (token, entry["TRACK_TOKEN_EXPIRE"].intValue ?? 0)
        }
        for index in stale {
            if let update = fresh[tracks[index].id] {
                tracks[index].trackToken = update.token
                tracks[index].trackTokenExpires = update.expires
            }
        }
        return tracks
    }
}

extension Track {
    /// This track's tags over `source`'s stream: the fields deemix's parseEssentialData swaps.
    func streaming(from source: Track) -> Track {
        var track = self
        track.id = source.id
        track.duration = source.duration
        track.trackToken = source.trackToken
        track.trackTokenExpires = source.trackTokenExpires
        track.md5Origin = source.md5Origin
        track.filesizes = source.filesizes
        track.fallbackID = source.fallbackID
        track.searched = source.searched
        return track
    }
}

extension Array where Element: Sendable {
    /// Every element through `transform` with `width` in flight at once, so a long list isn't
    /// one round trip after another. Results keep the elements' order.
    func concurrentMap<Value: Sendable>(
        width: Int = 4, _ transform: @escaping @Sendable (Element) async -> Value
    ) async -> [Value] {
        await withTaskGroup(of: (Int, Value).self) { group in
            var values = [Value?](repeating: nil, count: count)
            for (index, element) in enumerated() {
                if index >= width, let done = await group.next() { values[done.0] = done.1 }
                group.addTask { (index, await transform(element)) }
            }
            for await done in group { values[done.0] = done.1 }
            return values.compactMap { $0 }
        }
    }

    /// Each batch of a request Deezer caps at `size` items. Answers come back in batch order.
    fileprivate func batches<Answer: Sendable>(
        of size: Int, _ request: @escaping @Sendable ([Element]) async throws -> Answer
    ) async throws -> [([Element], Answer)] {
        let batches = stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
        let answers = await batches.concurrentMap { batch -> Result<Answer, any Error> in
            do { return .success(try await request(batch)) } catch { return .failure(error) }
        }
        return try zip(batches, answers).map { ($0, try $1.get()) }
    }
}
