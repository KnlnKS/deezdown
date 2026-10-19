import Foundation
import Testing
@testable import DeezDownKit

private let liveARL = ProcessInfo.processInfo.environment["DEEZDOWN_TEST_ARL"]

@Suite(.enabled(if: liveARL != nil, "set DEEZDOWN_TEST_ARL to run live Deezer tests"), .serialized)
struct LiveEngine {
    private func sandbox() throws -> (AppPaths, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "deezdown-engine-\(UUID().uuidString)")
        let music = root.appending(path: "music")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        return (AppPaths(configDirectory: root.appending(path: "config")), music)
    }

    private func drain(_ engine: DownloadEngine) async -> [QueueItem] {
        for await queue in await engine.events() where queue.allSatisfy(\.status.isFinished) {
            return queue
        }
        return await engine.queue
    }

    @Test func `an album downloads, names, and tags every track`() async throws {
        let (appPaths, music) = try sandbox()
        defer { try? FileManager.default.removeItem(at: appPaths.configDirectory.deletingLastPathComponent()) }

        let session = DeezerSession()
        try await session.login(arl: #require(liveARL))

        var settings = DownloadSettings()
        settings.downloadLocation = music.path(percentEncoded: false)
        settings.maxBitrate = .mp3_128
        settings.createM3U8File = true
        settings.queueConcurrency = 8

        let engine = DownloadEngine(session: session, settings: settings, queueDirectory: appPaths.queueDirectory)
        let started = ContinuousClock.now
        try await engine.enqueue([.album("302127")])
        let finished = await drain(engine)
        let elapsed = ContinuousClock.now - started

        let item = try #require(finished.first)
        #expect(item.status == .completed, "issues: \(item.issues.map(\.message))")
        #expect(item.totalTracks == 14)
        #expect(item.completedTracks == 14)
        #expect(item.failedTracks == 0)

        let folder = music.appending(path: "Daft Punk - Discovery")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            .sorted()
        #expect(files.filter { $0.hasSuffix(".mp3") }.count == 14)
        #expect(files.contains("cover.jpg"))
        #expect(files.contains("playlist.m3u8"))
        #expect(files.contains("04 - Harder, Better, Faster, Stronger.mp3"))

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let bytes = files.filter { $0.hasSuffix(".mp3") }.reduce(0) { total, name in
            total + ((try? FileManager.default.attributesOfItem(
                atPath: folder.appending(path: name).path(percentEncoded: false))[.size] as? Int) ?? 0)
        }
        print("  album: 14 tracks, \(bytes / 1_000_000) MB in \(String(format: "%.1f", seconds))s")
    }

    @Test func `a single track lands in the download root with the plain template`() async throws {
        let (appPaths, music) = try sandbox()
        defer { try? FileManager.default.removeItem(at: appPaths.configDirectory.deletingLastPathComponent()) }

        let session = DeezerSession()
        try await session.login(arl: #require(liveARL))
        var settings = DownloadSettings()
        settings.downloadLocation = music.path(percentEncoded: false)
        settings.maxBitrate = .mp3_128

        let engine = DownloadEngine(session: session, settings: settings, queueDirectory: appPaths.queueDirectory)
        try await engine.enqueue([.track("3135556")])
        let finished = await drain(engine)

        #expect(finished.first?.status == .completed)
        let expected = music.appending(path: "Daft Punk - Harder, Better, Faster, Stronger.mp3")
        #expect(FileManager.default.fileExists(atPath: expected.path(percentEncoded: false)))
    }

    @Test func `the queue survives a restart`() async throws {
        let (appPaths, music) = try sandbox()
        defer { try? FileManager.default.removeItem(at: appPaths.configDirectory.deletingLastPathComponent()) }

        let session = DeezerSession()
        try await session.login(arl: #require(liveARL))
        var settings = DownloadSettings()
        settings.downloadLocation = music.path(percentEncoded: false)

        let engine = DownloadEngine(session: session, settings: settings, queueDirectory: appPaths.queueDirectory)
        try await engine.enqueue([.album("302127")])
        await engine.cancelAll()

        let restored = DownloadEngine(session: session, settings: settings, queueDirectory: appPaths.queueDirectory)
        await restored.restore()
        let queue = await restored.queue
        #expect(queue.count == 1)
        #expect(queue.first?.id == "album_302127_9")
    }
}
