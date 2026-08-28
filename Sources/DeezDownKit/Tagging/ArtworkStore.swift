import Foundation

/// Fetches cover art once per album/size and hands the same bytes to every track in the batch.
public actor ArtworkStore {
    private let urlSession: URLSession
    private var cache: [URL: Data] = [:]
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": DeezerSession.userAgent]
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 20
        urlSession = URLSession(configuration: configuration)
    }

    public func image(_ picture: Artwork, size: Int, format: ImageFormat) async -> Data? {
        guard let url = picture.url(size: size, format: format) else { return nil }
        if let cached = cache[url] { return cached }
        if let running = inFlight[url] { return await running.value }

        let task = Task<Data?, Never> { [urlSession] in
            if let data = await Self.fetch(url, using: urlSession) { return data }
            // Deezer degrades above 1200px and answers larger requests with an error.
            guard size > 1200, let fallback = picture.url(size: 1200, format: format) else { return nil }
            return await Self.fetch(fallback, using: urlSession)
        }
        inFlight[url] = task
        let data = await task.value
        inFlight[url] = nil
        if let data, !data.isEmpty { cache[url] = data }
        return data
    }

    private static func fetch(_ url: URL, using session: URLSession) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty
        else { return nil }
        return data
    }

    public func clear() {
        cache.removeAll()
    }
}
