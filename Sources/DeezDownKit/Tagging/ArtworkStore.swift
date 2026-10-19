import Foundation

/// Fetches each picture once and hands the same bytes to every track that asks while it is fresh.
public actor ArtworkStore {
    private let urlSession: URLSession
    private var cache: [URL: Data] = [:]
    private var cachedOrder: [URL] = []
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
            // Not every cover exists above 1200px.
            guard size > 1200, let fallback = picture.url(size: 1200, format: format) else { return nil }
            return await Self.fetch(fallback, using: urlSession)
        }
        inFlight[url] = task
        let data = await task.value
        inFlight[url] = nil
        if let data, !data.isEmpty { remember(data, for: url) }
        return data
    }

    /// One album's tracks finish close together, so a short memory serves them all without
    /// holding every cover of a long playlist.
    private func remember(_ data: Data, for url: URL) {
        guard cache.updateValue(data, forKey: url) == nil else { return }
        cachedOrder.append(url)
        if cachedOrder.count > 32 { cache[cachedOrder.removeFirst()] = nil }
    }

    private static func fetch(_ url: URL, using session: URLSession) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty
        else { return nil }
        return data
    }
}
