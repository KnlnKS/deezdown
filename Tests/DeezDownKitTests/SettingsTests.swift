import Foundation
import Testing
@testable import DeezDownKit

@Test func `a partial or partly unreadable config keeps every value it can read`() throws {
    let sandbox = try Sandbox()
    let paths = AppPaths(configDirectory: sandbox.root)

    // deemix stores numbers as strings; an unknown choice must cost only itself.
    try Data(#"{"maxBitrate":"1","queueConcurrency":3,"overwriteFile":"?","tags":{"lyrics":true}}"#.utf8)
        .write(to: paths.settingsFile)

    let settings = SettingsStore(paths: paths).load()
    #expect(settings.maxBitrate == .mp3_128)
    #expect(settings.queueConcurrency == 3)
    #expect(settings.overwriteFile == DownloadSettings().overwriteFile)
    #expect(settings.tags.lyrics)
    #expect(settings.tags.title)
    #expect(settings.albumTracknameTemplate == "%tracknumber% - %title%")
    #expect(!settings.downloadLocation.isEmpty)
}

@Test func `settings survive a save and reload round trip`() throws {
    let sandbox = try Sandbox()
    let paths = AppPaths(configDirectory: sandbox.root)

    var settings = DownloadSettings()
    settings.maxBitrate = .mp3_320
    settings.overwriteFile = .keepBoth
    settings.featuredToTitle = .moveToTitle
    settings.tags.multiArtistSeparator = .andFeat
    settings.albumNameTemplate = "%album% (%year%)"
    try SettingsStore(paths: paths).save(settings)

    #expect(SettingsStore(paths: paths).load() == settings)
}
