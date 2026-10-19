import Foundation

public final class MediaDownloader: Sendable {
    private let urlSession: URLSession
    private let bodies: ResponseBodies

    public init(maximumConnectionsPerHost: Int = 12) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": DeezerSession.userAgent]
        configuration.httpMaximumConnectionsPerHost = maximumConnectionsPerHost
        configuration.timeoutIntervalForRequest = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let bodies = ResponseBodies()
        self.bodies = bodies
        urlSession = URLSession(configuration: configuration, delegate: bodies, delegateQueue: nil)
    }

    deinit {
        urlSession.finishTasksAndInvalidate()
    }

    /// Deezer only enciphers streams served from these paths.
    static func isEncrypted(_ url: URL) -> Bool {
        let path = url.path()
        return path.contains("/media/") || path.contains("/mobile/")
    }

    @discardableResult
    public func download(
        _ media: ResolvedMedia,
        to destination: URL,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws -> Int64 {
        var lastFailure = DownloadFailure(.notAvailable)
        for url in media.urls {
            do {
                return try await stream(url, trackID: media.track.id, to: destination, onProgress: onProgress)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastFailure = DownloadFailure(error)
                // Another mirror would only fill the disk again.
                if lastFailure.reason == .noSpaceLeft { break }
            }
        }
        throw lastFailure
    }

    private func stream(
        _ url: URL,
        trackID: String,
        to destination: URL,
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> Int64 {
        let (response, body) = try await bodies.start(urlSession.dataTask(with: url))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadFailure(.network("HTTP \(http.statusCode)"))
        }
        let expected = response.expectedContentLength
        if expected == 0 { throw DownloadFailure(.emptyStream) }

        let partial = destination.appendingPathExtension("part")
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var written: Int64 = 0

        do {
            try Data().write(to: partial)
            let handle = try FileHandle(forWritingTo: partial)
            defer { try? handle.close() }
            let decryptor = Self.isEncrypted(url) ? try StripeDecryptor(trackID: trackID) : nil
            for try await chunk in body {
                try Task.checkCancellation()
                if let decryptor {
                    let output = try decryptor.consume(chunk)
                    if !output.isEmpty { try handle.write(contentsOf: output) }
                } else {
                    try handle.write(contentsOf: chunk)
                }
                written += Int64(chunk.count)
                onProgress?(written, expected)
            }
            // A canceled stream simply ends, which must not pass for a complete file.
            try Task.checkCancellation()
            if let decryptor {
                let tail = try decryptor.finish()
                if !tail.isEmpty { try handle.write(contentsOf: tail) }
            }
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }

        if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: partial, to: destination)
        onProgress?(written, written)
        return written
    }
}
