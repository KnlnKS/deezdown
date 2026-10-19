import Foundation
import Testing
@testable import DeezDownKit

private func sampleTrack(explicit: Bool = false, discs: Int = 1) -> Track {
    let album = Album(
        id: "302127", title: "Discovery",
        mainArtist: ArtistRef(id: "27", name: "Daft Punk"), artists: ["Daft Punk"],
        genres: ["Electro"], label: "Daft Life Ltd.", barcode: "724384960650",
        date: CustomDate(deezerString: "2001-03-12"), trackTotal: 14, discTotal: discs
    )
    return Track(
        gateway: .object([
            "SNG_ID": "3135556", "SNG_TITLE": "Harder, Better, Faster, Stronger",
            "DURATION": "226", "TRACK_NUMBER": "4", "DISK_NUMBER": "1", "ISRC": "GBDUW0000059",
            "MD5_ORIGIN": "000790eceb6cb6732d225c0585632b31",
            "ARTISTS": .array([
                .object(["ART_ID": "27", "ART_NAME": "Daft Punk", "ROLE_ID": 0, "ART_PICTURE": "abc"]),
                .object(["ART_ID": "99", "ART_NAME": "Pharrell", "ROLE_ID": 5, "ART_PICTURE": "def"]),
            ]),
            "EXPLICIT_TRACK_CONTENT": .object(["EXPLICIT_LYRICS_STATUS": explicit ? 1 : 0]),
            "PHYSICAL_RELEASE_DATE": "2001-03-12",
        ]),
        album: album
    )
}

private func path(_ url: URL) -> String {
    let text = url.path(percentEncoded: false)
    return text.count > 1 && text.hasSuffix("/") ? String(text.dropLast()) : text
}

@Test func `illegal path characters are replaced and the name is normalised`() {
    #expect(NameSanitizer.fixName("AC/DC: Back?", replacer: "_") == "AC_DC_ Back_")
    #expect(NameSanitizer.fixName(#"a\b*c"d<e>f|g"#, replacer: "-") == "a-b-c-d-e-f-g")
    #expect(NameSanitizer.fixName("AC/DC", replacer: "") == "ACDC")
}

@Test func `only a slash in the template itself makes a folder`() {
    var settings = DownloadSettings()
    settings.downloadLocation = "/Music"
    settings.albumNameTemplate = "%year%/%album%"
    settings.albumTracknameTemplate = "%album%: %title%"
    var track = sampleTrack().applying(settings)
    track.title = "Harder/Better"
    let paths = PathBuilder(settings: settings).paths(for: track, context: DownloadContext())
    #expect(path(paths.directory) == "/Music/2001/Discovery")
    #expect(paths.filename == "Discovery_ Harder_Better")
}

@Test func `components that would vanish in finder fall back to a usable name`() {
    #expect(NameSanitizer.antiDot("...") == "dot")
    #expect(NameSanitizer.antiDot("Album.") == "Album")
    #expect(NameSanitizer.antiDot("Mr. Bungle") == "Mr. Bungle")
    #expect(
        NameSanitizer.fixLongName(String(repeating: "が", count: 100))
            == String(repeating: "が", count: NameSanitizer.segmentLimit / 3)
    )
}

@Test func `track numbers pad against the album total`() {
    var settings = DownloadSettings()
    #expect(NameSanitizer.pad(4, total: 14, settings: settings) == "04")
    #expect(NameSanitizer.pad(4, total: 140, settings: settings) == "004")
    #expect(NameSanitizer.pad(4, total: 9, settings: settings) == "04")
    settings.padSingleDigit = false
    #expect(NameSanitizer.pad(4, total: 9, settings: settings) == "4")
    settings.paddingSize = 5
    #expect(NameSanitizer.pad(4, total: 9, settings: settings) == "00004")
    settings.padTracks = false
    #expect(NameSanitizer.pad(4, total: 9, settings: settings) == "4")
}

@Test func `empty featured artists and explicit markers take their leading space with them`() {
    #expect(TemplateEngine.render("%title% %featartists%", ["title": "Song", "featartists": ""]) == "Song")
    #expect(
        TemplateEngine.render("%title% %featartists%", ["title": "Song", "featartists": "(feat. X)"])
            == "Song (feat. X)"
    )
    #expect(TemplateEngine.render("%title% %explicit%", ["title": "Song", "explicit": ""]) == "Song")
}

@Test func `an album download lands in artist and album folders when asked`() {
    var settings = DownloadSettings()
    settings.downloadLocation = "/Music"
    settings.createArtistFolder = true
    let track = sampleTrack().applying(settings)
    let paths = PathBuilder(settings: settings).paths(for: track, context: DownloadContext())

    #expect(path(paths.directory) == "/Music/Daft Punk/Daft Punk - Discovery")
    #expect(paths.artistDirectory.map(path(_:)) == "/Music/Daft Punk")
    #expect(paths.filename == "04 - Harder, Better, Faster, Stronger")
}

@Test func `a multi disc album gets CD folders`() {
    var settings = DownloadSettings()
    settings.downloadLocation = "/Music"
    let track = sampleTrack(discs: 2).applying(settings)
    let paths = PathBuilder(settings: settings).paths(for: track, context: DownloadContext())
    #expect(paths.directory.lastPathComponent == "CD1")
    #expect(paths.coverDirectory?.lastPathComponent == "Daft Punk - Discovery")
}

@Test func `a single track download uses the plain template and no album folder`() {
    var settings = DownloadSettings()
    settings.downloadLocation = "/Music"
    let track = sampleTrack().applying(settings)
    let paths = PathBuilder(settings: settings)
        .paths(for: track, context: DownloadContext(isSingleTrackDownload: true))
    #expect(path(paths.directory) == "/Music")
    #expect(paths.filename == "Daft Punk - Harder, Better, Faster, Stronger")
}

@Test func `a playlist download uses the playlist folder and template`() {
    var settings = DownloadSettings()
    settings.downloadLocation = "/Music"
    let playlist = Playlist(id: "123", title: "Road Trip", owner: "Kunalan", trackCount: 100)
    var track = sampleTrack().applying(settings)
    track.position = 7
    let paths = PathBuilder(settings: settings)
        .paths(for: track, context: DownloadContext(playlist: playlist))
    #expect(path(paths.directory) == "/Music/Road Trip")
    #expect(paths.filename == "Daft Punk - Harder, Better, Faster, Stronger")
    settings.playlistTracknameTemplate = "%position%"
    #expect(PathBuilder(settings: settings).paths(for: track, context: DownloadContext(playlist: playlist)).filename == "007")
}

@Test func `explicit tracks can be marked in the filename`() {
    var settings = DownloadSettings()
    settings.downloadLocation = "/Music"
    settings.albumTracknameTemplate = "%tracknumber% - %title% %explicit%"
    let track = sampleTrack(explicit: true).applying(settings)
    #expect(
        PathBuilder(settings: settings).paths(for: track, context: DownloadContext()).filename
            == "04 - Harder, Better, Faster, Stronger (Explicit)"
    )
}
