import Foundation
import Testing
@testable import DeezDownKit

@Test func `duplicate artists that are substrings of another are dropped`() {
    #expect(Track.removingSubstringDuplicates(["Daft Punk", "Daft"]) == ["Daft Punk"])
    #expect(Track.removingSubstringDuplicates(["Kanye West", "Jay-Z"]) == ["Kanye West", "Jay-Z"])
    #expect(Track.removingSubstringDuplicates(["A", "A"]) == ["A"])
}

@Test(arguments: [
    ("Title (feat. Someone)", "Title"),
    ("Title [ft. Someone]", "Title"),
    ("Title feat. Someone", "Title"),
    ("Title feat. Someone (Remix)", "Title (Remix)"),
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

@Test func `gateway values decode leniently whether deezer sends strings or numbers`() {
    #expect(JSONValue.string("3135556").intValue == 3_135_556)
    #expect(JSONValue.string("").intValue == nil)
    #expect(JSONValue.int(3_135_556).stringValue == "3135556")
    #expect(JSONValue.string("1").boolValue == true)
    #expect(JSONValue.array([]).isEmpty)
    #expect(JSONValue.object(["a": 1])["a"].intValue == 1)
    #expect(JSONValue.object([:])["missing"].isEmpty)
}
