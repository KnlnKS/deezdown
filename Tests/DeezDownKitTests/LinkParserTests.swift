import Foundation
import Testing
@testable import DeezDownKit

@Test(arguments: [
    ("https://www.deezer.com/track/3135556", DeezerLink.track("3135556")),
    ("https://www.deezer.com/us/track/3135556", .track("3135556")),
    ("https://www.deezer.com/en/album/302127", .album("302127")),
    ("https://deezer.com/album/302127/", .album("302127")),
    ("https://www.deezer.com/playlist/1313621735?utm=x", .playlist("1313621735")),
    ("https://www.deezer.com/fr/artist/27", .artist("27", tab: .all)),
    ("https://www.deezer.com/artist/27/top_track", .artistTop("27")),
    ("https://www.deezer.com/artist/27/albums", .artist("27", tab: .album)),
    ("https://www.deezer.com/artist/27/discography", .artist("27", tab: .all)),
    ("https://www.deezer.com/track/isrc:GBDUW0000059", .track("isrc:GBDUW0000059")),
    ("https://www.deezer.com/album/upc:724384960650", .album("upc:724384960650")),
    ("https://www.deezer.com/track/-12345", .track("-12345")),
])
func `every deezer link shape deemix accepts is parsed`(input: String, expected: DeezerLink) throws {
    #expect(try LinkParser.parse(input) == expected)
}

@Test func `links that are not deezer or not downloadable are rejected distinctly`() {
    #expect(throws: LinkParseError.notRecognized("https://open.spotify.com/track/x")) {
        try LinkParser.parse("https://open.spotify.com/track/x")
    }
    #expect(throws: LinkParseError.self) { try LinkParser.parse("https://www.deezer.com/profile/12345") }
    #expect(throws: LinkParseError.self) { try LinkParser.parse("https://www.deezer.com/album/not-a-number") }
}

@Test func `queue identity encodes type, id and bitrate so two qualities coexist`() {
    #expect(QueueItem.identifier(for: .album("302127"), format: .flac) == "album_302127_9")
    #expect(QueueItem.identifier(for: .artist("27", tab: .single), format: .mp3_320) == "artist_27_single_3")
}
