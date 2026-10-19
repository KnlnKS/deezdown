import Foundation

public enum QueueStatus: String, Sendable, Codable, Equatable {
    case queued, resolving, downloading, paused, completed, withErrors, failed, canceled

    public var isFinished: Bool {
        [.completed, .withErrors, .failed, .canceled].contains(self)
    }

    public var isActive: Bool {
        self == .resolving || self == .downloading
    }
}

public struct TrackIssue: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var artist: String
    public var message: String
}

public struct QueueItem: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var link: DeezerLink
    public var title: String
    public var subtitle: String
    public var cover: Artwork
    public var format: TrackFormat
    public var status: QueueStatus
    public var totalTracks: Int
    public var completedTracks: Int
    public var failedTracks: Int
    public var progress: Double
    public var issues: [TrackIssue]
    public var destination: URL?
    public var rootArtist: ArtistRef?

    public init(id: String, link: DeezerLink, title: String, subtitle: String, cover: Artwork, format: TrackFormat) {
        self.id = id
        self.link = link
        self.title = title
        self.subtitle = subtitle
        self.cover = cover
        self.format = format
        status = .queued
        totalTracks = 0
        completedTracks = 0
        failedTracks = 0
        progress = 0
        issues = []
    }

    /// Bitrate is part of the identity, so the same album at two qualities is two queue entries.
    public static func identifier(for link: DeezerLink, format: TrackFormat) -> String {
        "\(link.kind)_\(link.identifier)_\(format.rawValue)"
    }

    public var canRetry: Bool { status == .withErrors || status == .failed || status == .canceled }
    public var canPause: Bool { status == .queued || status.isActive }
    public var canResume: Bool { status == .paused }
    /// Finished with nothing to look into; failures stay until they are read.
    public var canClear: Bool { status == .completed || status == .canceled }
}
