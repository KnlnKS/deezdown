import Foundation

public struct DownloadFailure: LocalizedError, Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case notOnDeezer
        case notEncoded
        case wrongBitrate
        case wrongLicense
        case notSpatial
        case notAvailable
        case noSpaceLeft
        case wrongGeolocation(String)
        case albumMissing
        case noReleases(ArtistTab)
        case emptyStream
        case network(String)
        case tagging(String)
    }

    public var reason: Reason
    public var exhaustedAlternatives: Bool

    public init(_ reason: Reason, exhaustedAlternatives: Bool = false) {
        self.reason = reason
        self.exhaustedAlternatives = exhaustedAlternatives
    }

    /// What a failed transfer means to the user: a full disk, or else the network.
    init(_ error: any Error) {
        if let failure = error as? DownloadFailure {
            self = failure
            return
        }
        let error = error as NSError
        let full =
            (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC))
            || (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError)
        self.init(full ? .noSpaceLeft : .network(error.localizedDescription))
    }

    public var errorDescription: String? {
        let base =
            switch reason {
            case .notOnDeezer: "Track not available on Deezer"
            case .notEncoded: "Track not yet encoded"
            case .wrongBitrate: "Track not found at the requested bitrate"
            case .wrongLicense: "Your account can't stream this quality"
            case .notSpatial: "Track has no 360 Reality Audio version"
            case .notAvailable: "No downloadable source for this track"
            case .noSpaceLeft: "No space left on the disk"
            case .wrongGeolocation(let country): "Not available in \(country)"
            case .albumMissing: "The album no longer exists"
            case .noReleases(let tab): "Nothing to download under \(tab.title)"
            case .emptyStream: "Deezer returned an empty stream"
            case .network(let detail): detail
            case .tagging(let detail): "Could not write tags: \(detail)"
            }
        return exhaustedAlternatives ? "\(base), and no alternative was found" : base
    }
}
