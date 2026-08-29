import Foundation

public actor DeezerSession {
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private static let gatewayURL = URL(string: "https://www.deezer.com/ajax/gw-light.php")!
    private static let publicAPIBase = URL(string: "https://api.deezer.com/")!
    private static let mediaURL = URL(string: "https://media.deezer.com/v1/get_url")!
    private static let licenseLifetime = Duration.seconds(3000)

    public private(set) var user: DeezerUser?

    private let urlSession: URLSession
    private let publicLimiter = RateLimiter(limit: 45, window: .seconds(5))
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var apiToken: String?
    private var arl: String?
    private var licenseRefreshedAt: ContinuousClock.Instant?
    private var userRefresh: Task<DeezerUser?, any Error>?

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": DeezerSession.userAgent]
        configuration.httpMaximumConnectionsPerHost = 12
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = true
        urlSession = URLSession(configuration: configuration)
    }

    public var isLoggedIn: Bool { user != nil }

    @discardableResult
    public func login(arl candidate: String) async throws -> DeezerUser {
        let trimmed = candidate.filter { !$0.isWhitespace }
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isHexDigit) else { throw DeezerError.invalidARL }

        apiToken = nil
        user = nil
        arl = trimmed
        urlSession.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
        setCookie(name: "arl", value: trimmed)

        let results = try await gateway("deezer.getUserData")
        guard let loaded = makeUser(from: results) else { throw DeezerError.invalidARL }
        user = loaded
        licenseRefreshedAt = .now
        return loaded
    }

    public func logout() {
        user = nil
        apiToken = nil
        arl = nil
        urlSession.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    }

    public func licenseToken() async throws -> String {
        guard let current = user else { throw DeezerError.notLoggedIn }
        if let refreshedAt = licenseRefreshedAt, ContinuousClock.now - refreshedAt < Self.licenseLifetime {
            return current.licenseToken
        }
        return try await refreshedUser()?.licenseToken ?? current.licenseToken
    }

    /// One refresh at a time. A queue resolving several albums at once would otherwise send
    /// the same user-data request from every batch in flight.
    private func refreshedUser() async throws -> DeezerUser? {
        if let refreshing = userRefresh { return try await refreshing.value }
        let refresh = Task { () throws -> DeezerUser? in
            guard let loaded = makeUser(from: try await gateway("deezer.getUserData")) else { return nil }
            user = loaded
            licenseRefreshedAt = .now
            return loaded
        }
        userRefresh = refresh
        defer { userRefresh = nil }
        return try await refresh.value
    }

    private func makeUser(from results: JSONValue) -> DeezerUser? {
        guard !results.objectValue.isEmpty else { return nil }
        let candidate = DeezerUser(results: results)
        guard candidate.id != "0", !candidate.id.isEmpty else { return nil }
        return candidate
    }

    private func setCookie(name: String, value: String) {
        guard let cookie = HTTPCookie(properties: [
            .domain: ".deezer.com",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
        ]) else { return }
        urlSession.configuration.httpCookieStorage?.setCookie(cookie)
    }

    // MARK: - Gateway

    @discardableResult
    public func gateway(
        _ method: String,
        _ arguments: [String: JSONValue] = [:],
        parameters: [String: String] = [:]
    ) async throws -> JSONValue {
        var arguments = arguments
        var attempt = 0

        while true {
            attempt += 1
            let token = method == "deezer.getUserData" ? "null" : try await resolvedAPIToken()
            var components = URLComponents(url: Self.gatewayURL, resolvingAgainstBaseURL: false)!
            components.queryItems =
                [
                    URLQueryItem(name: "method", value: method),
                    URLQueryItem(name: "input", value: "3"),
                    URLQueryItem(name: "api_version", value: "1.0"),
                    URLQueryItem(name: "api_token", value: token),
                ] + parameters.map { URLQueryItem(name: $0.key, value: $0.value) }

            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let language = user?.language { request.setValue(language, forHTTPHeaderField: "Accept-Language") }
            request.httpBody = try encoder.encode(JSONValue.object(arguments))

            let body: JSONValue
            do {
                body = try await send(request)
            } catch {
                guard attempt < 3, isTransient(error) else { throw error }
                try await Task.sleep(for: .seconds(2))
                continue
            }

            if method == "deezer.getUserData", let form = body["results"]["checkForm"].stringValue {
                apiToken = form
            }

            let failure = body["error"]
            if !failure.isEmpty {
                let text = failure.objectValue.values.compactMap(\.stringValue).joined(separator: " ")
                let retriable =
                    text.localizedCaseInsensitiveContains("invalid api token")
                    || text.localizedCaseInsensitiveContains("Invalid CSRF token")
                    || failure["NEED_API_AUTH_REQUIRED"] != .null
                if retriable, attempt < 3 {
                    apiToken = nil
                    continue
                }
                throw DeezerError.gateway(text.isEmpty ? "\(failure)" : text)
            }

            let fallback = body["payload"]["FALLBACK"].objectValue
            if !fallback.isEmpty, attempt < 3 {
                arguments.merge(fallback) { _, new in new }
                continue
            }

            return body["results"]
        }
    }

    private func resolvedAPIToken() async throws -> String {
        if let apiToken { return apiToken }
        _ = try await refreshedUser()
        guard let apiToken else { throw DeezerError.badResponse }
        return apiToken
    }

    // MARK: - Public API

    public func publicAPI(_ path: String, query: [String: String] = [:]) async throws -> JSONValue {
        var attempt = 0
        while true {
            attempt += 1
            try await publicLimiter.acquire()

            var components = URLComponents(
                url: Self.publicAPIBase.appending(path: path),
                resolvingAgainstBaseURL: false
            )!
            if !query.isEmpty {
                components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            }

            let body: JSONValue
            do {
                body = try await send(URLRequest(url: components.url!))
            } catch {
                guard attempt < 4, isTransient(error) else { throw error }
                try await Task.sleep(for: .seconds(attempt))
                continue
            }

            let failure = body["error"]
            if !failure.isEmpty {
                let code = failure["code"].intValue ?? 0
                if (code == 4 || code == 700), attempt < 4 {
                    try await Task.sleep(for: .seconds(attempt * 2))
                    continue
                }
                throw DeezerError.publicAPI(code: code, message: failure["message"].stringValue ?? "")
            }
            return body
        }
    }

    // MARK: - Media

    public func trackURLs(trackTokens: [String], format: TrackFormat) async throws -> [MediaResult] {
        guard let user else { throw DeezerError.notLoggedIn }
        guard user.canStream(format) else { throw DeezerError.wrongLicense(format) }
        guard !trackTokens.isEmpty else { return [] }

        let license = try await licenseToken()
        var request = URLRequest(url: Self.mediaURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            JSONValue.object([
                "license_token": .string(license),
                "media": .array([
                    .object([
                        "type": "FULL",
                        "formats": .array([.object(["cipher": "BF_CBC_STRIPE", "format": .string(format.apiName)])]),
                    ])
                ]),
                "track_tokens": .array(trackTokens.map(JSONValue.string)),
            ])
        )

        let body = try await send(request)
        return body["data"].arrayValue.map { entry in
            let sources = entry["media"][0]["sources"].arrayValue
                .compactMap { URL(string: $0["url"].stringValue ?? "") }
            if let primary = sources.first {
                return .success(primary: primary, mirrors: Array(sources.dropFirst()))
            }
            let code = entry["errors"][0]["code"].intValue ?? 0
            return .failure(code: code, message: entry["errors"][0]["message"].stringValue ?? "")
        }
    }

    // MARK: - Transport

    private func send(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DeezerError.http(http.statusCode)
        }
        return try decoder.decode(JSONValue.self, from: data)
    }

    private func isTransient(_ error: any Error) -> Bool {
        if case DeezerError.http(let status) = error { return status >= 500 || status == 429 }
        let code = (error as NSError).code
        return [
            NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost,
            NSURLErrorNotConnectedToInternet, NSURLErrorDNSLookupFailed,
        ].contains(code)
    }
}

public enum MediaResult: Sendable, Equatable {
    case success(primary: URL, mirrors: [URL])
    case failure(code: Int, message: String)

    public var urls: [URL] {
        if case .success(let primary, let mirrors) = self { return [primary] + mirrors }
        return []
    }
}
