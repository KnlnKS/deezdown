import Foundation
import Testing
@testable import DeezDownKit

@Suite(.live, .serialized)
struct LiveSession {
    let session = DeezerSession()

    @discardableResult
    private func signedIn() async throws -> DeezerUser {
        try await session.login(arl: #require(liveARL))
    }

    @Test func `signing in with an ARL yields a user and a license token`() async throws {
        let user = try await signedIn()
        #expect(user.id != "0")
        #expect(!user.licenseToken.isEmpty)
        #expect(!user.country.isEmpty)
    }

    @Test func `a garbage ARL is rejected rather than silently signing in anonymously`() async throws {
        await #expect(throws: DeezerError.self) {
            try await session.login(arl: String(repeating: "a", count: 192))
        }
    }

    @Test func `a bad track token reports an error instead of a url`() async throws {
        try await signedIn()
        let results = try await session.trackURLs(trackTokens: ["bogus"], format: .mp3_128)
        #expect(results == [.failure(code: 2000, message: "An error occurred while decoding track token.")])
    }

    @Test func `search and artists resolve`() async throws {
        try await signedIn()
        let (tracks, total) = try await session.search(query: "daft punk", kind: .track, limit: 5)
        #expect(!tracks.isEmpty && total > 0)

        let artist = try await session.artistData(id: "27")
        #expect(artist["ART_NAME"].stringValue == "Daft Punk")
    }
}
