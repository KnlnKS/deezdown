import Foundation
import Testing
@testable import DeezDownKit

private let liveARL = ProcessInfo.processInfo.environment["DEEZDOWN_TEST_ARL"]

@Suite(.enabled(if: liveARL != nil, "set DEEZDOWN_TEST_ARL to run live Deezer tests"), .serialized)
struct LiveSession {
    let session = DeezerSession()

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

    @Test func `an album resolves its whole tracklist with track tokens in one call`() async throws {
        try await signedIn()
        let tracks = try await session.albumTracks(id: "302127")
        #expect(tracks.count == 14)
        #expect(tracks.allSatisfy { $0["TRACK_TOKEN"].stringValue?.isEmpty == false })
    }

    @Test func `track data carries the fields the downloader depends on`() async throws {
        try await signedIn()
        let track = try await session.trackData(id: "3135556")
        #expect(track["SNG_TITLE"].stringValue == "Harder, Better, Faster, Stronger")
        #expect(track["MD5_ORIGIN"].stringValue == "000790eceb6cb6732d225c0585632b31")
        #expect(track["ISRC"].stringValue == "GBDUW0000059")
        #expect((track["FILESIZE_FLAC"].intValue ?? 0) > 0)
    }

    @Test func `media urls come back for a batch of tokens with mirrors`() async throws {
        let user = try await signedIn()
        let tracks = try await session.albumTracks(id: "302127")
        let tokens = tracks.compactMap { $0["TRACK_TOKEN"].stringValue }
        let results = try await session.trackURLs(trackTokens: tokens, format: user.highestAvailableFormat)
        #expect(results.count == tokens.count)
        #expect(results.allSatisfy { $0.urls.count >= 1 })
    }

    @Test func `a bad track token reports an error instead of a url`() async throws {
        try await signedIn()
        let results = try await session.trackURLs(trackTokens: ["bogus"], format: .mp3_128)
        #expect(results == [.failure(code: 2000, message: "An error occurred while decoding track token.")])
    }

    @Test func `search, lyrics, playlists and artists all resolve`() async throws {
        try await signedIn()
        let (tracks, total) = try await session.search(query: "daft punk", kind: .track, limit: 5)
        #expect(!tracks.isEmpty && total > 0)

        let lyrics = try await session.lyrics(trackID: "3135556")
        #expect(lyrics["LYRICS_TEXT"].stringValue?.isEmpty == false)

        let playlist = try await session.playlistTracks(id: "1313621735")
        #expect(!playlist.isEmpty)

        let artist = try await session.artistData(id: "27")
        #expect(artist["ART_NAME"].stringValue == "Daft Punk")
    }
}
