import Foundation

public enum DeezerError: Error, Sendable {
    case notLoggedIn
    case invalidARL
    case gateway(String)
    case publicAPI(code: Int, message: String)
    case http(Int)
    case badResponse
}

extension DeezerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: "Not signed in to Deezer."
        case .invalidARL: "That ARL is not valid or has expired."
        case .gateway(let detail): "Deezer rejected the request: \(detail)"
        case .publicAPI(let code, let message): "Deezer API error \(code): \(message)"
        case .http(let status): "Deezer returned HTTP \(status)."
        case .badResponse: "Deezer returned a response that could not be read."
        }
    }
}
