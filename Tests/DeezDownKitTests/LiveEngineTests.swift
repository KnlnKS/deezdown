import Foundation
import Testing
@testable import DeezDownKit

/// Each test gets its own instance, so its own folder to download into.
@Suite(.live, .serialized)
final class LiveEngine {
    let session = DeezerSession()
    let sandbox: Sandbox
    var music: URL { sandbox.root.appending(path: "music") }
    var settings = DownloadSettings()

    init() throws {
        sandbox = try Sandbox()
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        settings.downloadLocation = music.path(percentEncoded: false)
    }

    /// Engines a test makes share one session and one queue folder.
    private func engine() async throws -> DownloadEngine {
        if await session.user == nil { try await session.login(arl: #require(liveARL)) }
        let paths = AppPaths(configDirectory: sandbox.root.appending(path: "config"))
        return await DownloadEngine(session: session, settings: settings, queueDirectory: paths.queueDirectory)
    }

    private func drain(_ engine: DownloadEngine) async -> [QueueItem] {
        for await queue in await engine.events() where queue.allSatisfy(\.status.isFinished) {
            return queue
        }
        return await engine.queue
    }

    @Test func `an album downloads, names, and tags every track`() async throws {
        settings.maxBitrate = .mp3_128
        settings.createM3U8File = true
        settings.queueConcurrency = 8
        let engine = try await engine()
        try await engine.enqueue([.album("302127")])
        let finished = await drain(engine)

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
    }

    @Test func `a single track lands in the download root with the plain template`() async throws {
        settings.maxBitrate = .mp3_128
        let engine = try await engine()
        try await engine.enqueue([.track("3135556")])
        let finished = await drain(engine)

        #expect(finished.first?.status == .completed)
        let expected = music.appending(path: "Daft Punk - Harder, Better, Faster, Stronger.mp3")
        #expect(FileManager.default.fileExists(atPath: expected.path(percentEncoded: false)))
    }

    @Test func `the queue survives a restart`() async throws {
        let engine = try await engine()
        try await engine.enqueue([.album("302127")])
        await engine.cancelAll()

        let restored = try await self.engine()
        let queue = await restored.queue
        #expect(queue.count == 1)
        #expect(queue.first?.id == "album_302127_9")
    }
}
