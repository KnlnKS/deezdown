import Foundation
import Testing
@testable import DeezDownKit

private func sandboxPaths() throws -> AppPaths {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "deezdown-cfg-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return AppPaths(configDirectory: root)
}

@Test func `a partial config keeps its own values and inherits the rest`() throws {
    let paths = try sandboxPaths()
    defer { try? FileManager.default.removeItem(at: paths.configDirectory) }

    try Data(#"{"maxBitrate":1,"queueConcurrency":3,"tags":{"lyrics":true}}"#.utf8)
        .write(to: paths.settingsFile)

    let settings = SettingsStore(paths: paths).load()
    #expect(settings.maxBitrate == .mp3_128)
    #expect(settings.queueConcurrency == 3)
    #expect(settings.tags.lyrics)
    #expect(settings.tags.title)
    #expect(settings.albumTracknameTemplate == "%tracknumber% - %title%")
    #expect(!settings.downloadLocation.isEmpty)
}

@Test func `a corrupt config falls back to defaults instead of failing`() throws {
    let paths = try sandboxPaths()
    defer { try? FileManager.default.removeItem(at: paths.configDirectory) }
    try Data("{ not json".utf8).write(to: paths.settingsFile)
    #expect(SettingsStore(paths: paths).load().maxBitrate == DownloadSettings().maxBitrate)
}

@Test func `settings survive a save and reload round trip`() throws {
    let paths = try sandboxPaths()
    defer { try? FileManager.default.removeItem(at: paths.configDirectory) }

    var settings = DownloadSettings()
    settings.maxBitrate = .mp3_320
    settings.overwriteFile = .keepBoth
    settings.featuredToTitle = .moveToTitle
    settings.tags.multiArtistSeparator = .andFeat
    settings.albumNameTemplate = "%album% (%year%)"
    try SettingsStore(paths: paths).save(settings)

    #expect(SettingsStore(paths: paths).load() == settings)
}

@Test func `repair clamps nonsense values instead of accepting them`() {
    var settings = DownloadSettings()
    settings.queueConcurrency = 500
    settings.jpegImageQuality = 0
    settings.albumTracknameTemplate = ""
    settings.downloadLocation = "  "
    settings.localArtworkFormat = "webp"
    settings.repair()

    #expect(settings.queueConcurrency == 16)
    #expect(settings.jpegImageQuality == 1)
    #expect(settings.albumTracknameTemplate == "%tracknumber% - %title%")
    #expect(!settings.downloadLocation.trimmingCharacters(in: .whitespaces).isEmpty)
    #expect(settings.localArtworkFormat == "jpg")
}
