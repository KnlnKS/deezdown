import Foundation
import Testing
@testable import DeezDownKit

@Test func `artist lists read the way deemix writes them`() {
    #expect(Track.andCommaConcat(["A"]) == "A")
    #expect(Track.andCommaConcat(["A", "B"]) == "A & B")
    #expect(Track.andCommaConcat(["A", "B", "C"]) == "A, B & C")
}

@Test func `duplicate artists that are substrings of another are dropped`() {
    #expect(Track.removingSubstringDuplicates(["Daft Punk", "Daft"]) == ["Daft Punk"])
    #expect(Track.removingSubstringDuplicates(["Kanye West", "Jay-Z"]) == ["Kanye West", "Jay-Z"])
    #expect(Track.removingSubstringDuplicates(["A", "A"]) == ["A"])
}

@Test(arguments: [
    ("Title (feat. Someone)", "Title"),
    ("Title [ft. Someone]", "Title"),
    ("Title feat. Someone", "Title"),
    ("Title", "Title"),
    ("Defeated", "Defeated"),
])
func `featured artists are stripped from titles without eating real words`(input: String, expected: String) {
    #expect(Track.removingFeatures(from: input) == expected)
}

@Test func `dates parse and render through every supported format`() throws {
    let date = try #require(CustomDate(deezerString: "2001-03-12"))
    #expect(date.year == "2001")
    #expect(date.month == "03")
    #expect(date.day == "12")
    #expect(date.formatted("Y-M-D") == "2001-03-12")
    #expect(date.formatted("D-M-Y") == "12-03-2001")
    #expect(date.formatted("Y") == "2001")
    #expect(CustomDate(deezerString: "0000-00-00") == nil)
}

@Test func `a day above twelve in the month slot is swapped back`() throws {
    var date = CustomDate(day: "03", month: "25", year: "2001")
    date.fixDayMonth()
    #expect(date.day == "25")
    #expect(date.month == "03")
}

@Test func `blank synced lines borrow the timestamp of the next timed line`() {
    let lyrics = Lyrics(results: .object([
        "LYRICS_ID": "1",
        "LYRICS_SYNC_JSON": .array([
            .object(["lrc_timestamp": "[00:01.00]", "milliseconds": 1000, "line": "first"]),
            .object(["lrc_timestamp": "", "milliseconds": 0, "line": ""]),
            .object(["lrc_timestamp": "[00:09.00]", "milliseconds": 9000, "line": "second"]),
        ]),
    ]))
    #expect(lyrics.lrc == "[00:01.00]first\r\n[00:09.00]\r\n[00:09.00]second\r\n")
    #expect(lyrics.id3Sync.map(\.text) == ["first", "second"])
}

@Test func `cover urls follow the deezer image cdn template`() throws {
    let cover = Artwork(md5: "5718f7c81c27e0b2417e2a4c45224f8a", kind: .cover)
    #expect(
        cover.url(size: 800, format: .jpeg(quality: 90))?.absoluteString
            == "https://cdn-images.dzcdn.net/images/cover/5718f7c81c27e0b2417e2a4c45224f8a/800x800-000000-90-0-0.jpg"
    )
    #expect(
        cover.url(size: 1200, format: .png)?.absoluteString
            == "https://cdn-images.dzcdn.net/images/cover/5718f7c81c27e0b2417e2a4c45224f8a/1200x1200-none-100-0-0.png"
    )
    #expect(Artwork(md5: "", kind: .cover).url(size: 800, format: .png) == nil)
}

@Test func `gateway values decode leniently whether deezer sends strings or numbers`() {
    #expect(JSONValue.string("3135556").intValue == 3_135_556)
    #expect(JSONValue.int(3_135_556).stringValue == "3135556")
    #expect(JSONValue.string("1").boolValue == true)
    #expect(JSONValue.array([]).isEmpty)
    #expect(JSONValue.object(["a": 1])["a"].intValue == 1)
    #expect(JSONValue.object([:])["missing"].isEmpty)
}
