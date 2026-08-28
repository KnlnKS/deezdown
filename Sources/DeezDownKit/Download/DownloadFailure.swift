import Foundation

public struct DownloadFailure: Error, Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case notOnDeezer
        case notEncoded
        case wrongBitrate
        case wrongLicense
        case notSpatial
        case notAvailable
        case noSpaceLeft
        case notLoggedIn
        case wrongGeolocation(String)
        case albumMissing
        case canceled
        case emptyStream
        case timedOut
        case network(String)
        case tagging(String)
    }

    public var reason: Reason
    public var exhaustedAlternatives: Bool

    public init(_ reason: Reason, exhaustedAlternatives: Bool = false) {
        self.reason = reason
        self.exhaustedAlternatives = exhaustedAlternatives
    }

    public var isCanceled: Bool { reason == .canceled }

    public var message: String {
        let base =
            switch reason {
            case .notOnDeezer: "Track not available on Deezer"
            case .notEncoded: "Track not yet encoded"
            case .wrongBitrate: "Track not found at the requested bitrate"
            case .wrongLicense: "Your account can't stream this quality"
            case .notSpatial: "Track has no 360 Reality Audio version"
            case .notAvailable: "No downloadable source for this track"
            case .noSpaceLeft: "No space left on the disk"
            case .notLoggedIn: "Not signed in to Deezer"
            case .wrongGeolocation(let country): "Not available in \(country)"
            case .albumMissing: "The album no longer exists"
            case .canceled: "Canceled"
            case .emptyStream: "Deezer returned an empty stream"
            case .timedOut: "The download timed out"
            case .network(let detail): detail
            case .tagging(let detail): "Could not write tags: \(detail)"
            }
        return exhaustedAlternatives ? "\(base), and no alternative was found" : base
    }
}

extension Collection {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [Array(self)] }
        var chunks: [[Element]] = []
        var current: [Element] = []
        current.reserveCapacity(size)
        for element in self {
            current.append(element)
            if current.count == size {
                chunks.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
