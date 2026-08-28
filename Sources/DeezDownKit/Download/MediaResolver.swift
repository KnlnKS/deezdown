import Foundation

public struct ResolvedMedia: Sendable, Equatable {
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

    public func ladder(for preferred: TrackFormat) -> [TrackFormat] {
        guard settings.fallbackBitrate else { return [preferred] }
        let family: [TrackFormat] =
            preferred.isSpatial ? [.mp4ra3, .mp4ra2, .mp4ra1] : [.flac, .mp3_320, .mp3_128]
        return family.filter { $0 <= preferred }
    }

    public func resolve(_ tracks: [Track], format preferred: TrackFormat) async throws
        -> [Result<ResolvedMedia, DownloadFailure>]
    {
        guard let user = await session.user else { throw DeezerError.notLoggedIn }

        var pending = try await refreshingExpiredTokens(tracks)
        var outcomes = [Result<ResolvedMedia, DownloadFailure>?](repeating: nil, count: pending.count)
        var unresolved = Array(pending.indices)
        var lastReason: [Int: DownloadFailure.Reason] = [:]

        for (index, track) in pending.enumerated() where !track.isEncoded && !track.isLocal {
            outcomes[index] = .failure(DownloadFailure(.notEncoded))
        }
        unresolved.removeAll { outcomes[$0] != nil }

        for format in ladder(for: preferred) {
            guard !unresolved.isEmpty else { break }
            guard user.canStream(format) else {
                for index in unresolved { lastReason[index] = .wrongLicense }
                continue
            }

            let candidates = unresolved.filter { pending[$0].filesize(for: format) > 0 }
            for index in unresolved where pending[index].filesize(for: format) == 0 {
                lastReason[index] = lastReason[index] ?? .wrongBitrate
            }
            guard !candidates.isEmpty else { continue }

            for batch in candidates.chunked(into: Self.batchLimit) {
                let tokens = batch.map { pending[$0].trackToken }
                let media = try await session.trackURLs(trackTokens: tokens, format: format)
                for (offset, index) in batch.enumerated() {
                    guard offset < media.count else { continue }
                    switch media[offset] {
                    case .success(let primary, let mirrors):
                        outcomes[index] = .success(
                            ResolvedMedia(track: pending[index], format: format, urls: [primary] + mirrors)
                        )
                    case .failure(let code, _):
                        lastReason[index] = code == 2002 ? .wrongGeolocation(user.country) : .notAvailable
                    }
                }
            }
            unresolved.removeAll { outcomes[$0] != nil }
        }

        if !unresolved.isEmpty {
            let recovered = try await resolveViaFallbackIDs(
                indices: unresolved, tracks: &pending, outcomes: &outcomes, format: preferred
            )
            unresolved.removeAll { recovered.contains($0) || outcomes[$0] != nil }
        }

        for index in unresolved {
            let reason = lastReason[index] ?? (preferred.isSpatial ? .notSpatial : .notAvailable)
            outcomes[index] = .failure(DownloadFailure(reason, exhaustedAlternatives: true))
        }

        return outcomes.map { $0 ?? .failure(DownloadFailure(.notAvailable, exhaustedAlternatives: true)) }
    }

    /// Deezer publishes replacement IDs for dead tracks; follow one hop for everything that failed.
    private func resolveViaFallbackIDs(
        indices: [Int],
        tracks: inout [Track],
        outcomes: inout [Result<ResolvedMedia, DownloadFailure>?],
        format preferred: TrackFormat
    ) async throws -> Set<Int> {
        let withFallback = indices.filter { tracks[$0].fallbackID != nil }
        guard !withFallback.isEmpty else { return [] }

        var replacements: [String: Track] = [:]
        for batch in withFallback.compactMap({ tracks[$0].fallbackID }).chunked(into: Self.batchLimit) {
            for entry in try await session.trackList(ids: batch) {
                let replacement = Track(gateway: entry)
                replacements[replacement.id] = replacement
            }
        }

        var candidates: [Int: Track] = [:]
        for index in withFallback {
            guard let fallbackID = tracks[index].fallbackID, var replacement = replacements[fallbackID] else {
                continue
            }
            replacement.playlist = tracks[index].playlist
            replacement.position = tracks[index].position
            replacement.fallbackID = nil
            candidates[index] = replacement
        }
        guard !candidates.isEmpty else { return [] }

        let ordered = candidates.keys.sorted()
        let resolved = try await resolve(ordered.map { candidates[$0]! }, format: preferred)

        var recovered: Set<Int> = []
        for (offset, index) in ordered.enumerated() {
            if case .success(let media) = resolved[offset] {
                outcomes[index] = .success(media)
                tracks[index] = media.track
                recovered.insert(index)
            }
        }
        return recovered
    }

    private func refreshingExpiredTokens(_ tracks: [Track]) async throws -> [Track] {
        var tracks = tracks
        let stale = tracks.indices.filter { tracks[$0].trackToken.isEmpty || tracks[$0].tokenIsExpired }
        guard !stale.isEmpty else { return tracks }

        var fresh: [String: (token: String, expires: Int)] = [:]
        for batch in stale.map({ tracks[$0].id }).chunked(into: Self.batchLimit) {
            for entry in try await session.trackList(ids: batch) {
                guard let id = entry["SNG_ID"].stringValue, let token = entry["TRACK_TOKEN"].stringValue else {
                    continue
                }
                fresh[id] = (token, entry["TRACK_TOKEN_EXPIRE"].intValue ?? 0)
            }
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
