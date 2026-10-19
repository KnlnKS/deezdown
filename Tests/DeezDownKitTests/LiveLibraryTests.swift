import Foundation
import Testing
@testable import DeezDownKit

@Suite(.live, .serialized)
struct LiveLibrary {
    let session = DeezerSession()

    private func library() async throws -> DeezerLibrary {
        try await session.login(arl: #require(liveARL))
        return DeezerLibrary(session: session)
    }

    @Test func `search returns every result type`() async throws {
        let results = try await library().search("daft punk", limit: 5)
        #expect(!results.tracks.isEmpty)
        #expect(!results.albums.isEmpty)
        #expect(!results.artists.isEmpty)
        #expect(results.artists.first?.name == "Daft Punk")
        #expect(results.tracks.first?.previewURL != nil)
    }

    @Test func `an album detail carries tracks, label and genre`() async throws {
        let detail = try await library().album(id: "302127")
        #expect(detail.summary.title == "Discovery")
        #expect(detail.tracks.count == 14)
        #expect(detail.genres.contains("Electro"))
        #expect(!detail.label.isEmpty)
        #expect(detail.duration > 3000)
    }

    @Test func `an artist detail carries a bio, top tracks and discography tabs`() async throws {
        let detail = try await library().artist(id: "27")
        #expect(detail.summary.name == "Daft Punk")
        #expect(!detail.topTracks.isEmpty)
        #expect(detail.albums[.all]?.isEmpty == false)
        #expect(detail.albums[.album]?.isEmpty == false)
        #expect(!detail.biography.contains("<"))
    }

    @Test func `playlists, favorites and charts load`() async throws {
        let library = try await library()
        let playlist = try await library.playlist(id: "1313621735")
        #expect(!playlist.tracks.isEmpty)

        _ = try await library.favorites()

        let charts = try await library.charts()
        #expect(!charts.albums.isEmpty || !charts.playlists.isEmpty)
    }
}
