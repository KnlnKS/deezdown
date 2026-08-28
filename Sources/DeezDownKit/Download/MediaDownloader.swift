import Foundation

public struct MediaDownloader: Sendable {
    public static let readBufferSize = 1 << 16

    private let urlSession: URLSession

    public init(maximumConnectionsPerHost: Int = 12) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": DeezerSession.userAgent]
        configuration.httpMaximumConnectionsPerHost = maximumConnectionsPerHost
        configuration.timeoutIntervalForRequest = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlSession = URLSession(configuration: configuration)
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
            } catch let failure as DownloadFailure {
                if failure.isCanceled { throw failure }
                lastFailure = failure
            } catch is CancellationError {
                throw DownloadFailure(.canceled)
            } catch {
                lastFailure = DownloadFailure(.network(error.localizedDescription))
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
        let (bytes, response) = try await urlSession.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadFailure(.network("HTTP \(http.statusCode)"))
        }
        let expected = response.expectedContentLength
        if expected == 0 { throw DownloadFailure(.emptyStream) }

        let partial = destination.appendingPathExtension("part")
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: partial.path(percentEncoded: false)) {
            try manager.removeItem(at: partial)
        }
        guard manager.createFile(atPath: partial.path(percentEncoded: false), contents: nil) else {
            throw DownloadFailure(.noSpaceLeft)
        }
        let handle = try FileHandle(forWritingTo: partial)

        let decryptor = Self.isEncrypted(url) ? try StripeDecryptor(trackID: trackID) : nil
        var buffer = [UInt8]()
        buffer.reserveCapacity(Self.readBufferSize)
        var written: Int64 = 0

        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count == Self.readBufferSize {
                    let output = try decryptor.map { try $0.consume(buffer) } ?? buffer
                    if !output.isEmpty { try handle.write(contentsOf: output) }
                    written += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    onProgress?(written, expected)
                    try Task.checkCancellation()
                }
            }
            if !buffer.isEmpty {
                let output = try decryptor.map { try $0.consume(buffer) } ?? buffer
                if !output.isEmpty { try handle.write(contentsOf: output) }
                written += Int64(buffer.count)
            }
            if let decryptor {
                let tail = try decryptor.finish()
                if !tail.isEmpty { try handle.write(contentsOf: tail) }
            }
            try handle.close()
        } catch is CancellationError {
            try? handle.close()
            try? manager.removeItem(at: partial)
            throw DownloadFailure(.canceled)
        } catch {
            try? handle.close()
            try? manager.removeItem(at: partial)
            throw DownloadFailure(.network(error.localizedDescription))
        }

        if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: partial, to: destination)
        onProgress?(written, written)
        return written
    }
}
