import Foundation
import Testing
@testable import DeezDownKit

private let liveARL = ProcessInfo.processInfo.environment["DEEZDOWN_TEST_ARL"]

/// Runs one of Homebrew's ffmpeg tools and returns everything it printed.
@discardableResult
private func ffmpeg(_ tool: String, _ arguments: String...) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/\(tool)")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: output, as: UTF8.self)
}

@Suite(.enabled(if: liveARL != nil, "set DEEZDOWN_TEST_ARL to run live Deezer tests"), .serialized)
struct LiveDownload {
    let session = DeezerSession()

    @Test(arguments: [TrackFormat.flac, .mp3_320])
    func `a downloaded track decodes cleanly end to end`(format: TrackFormat) async throws {
        try await session.login(arl: #require(liveARL))
        let track = Track(gateway: try await session.trackData(id: "3135556"))
        #expect(track.isEncoded)

        let resolver = MediaResolver(session: session, settings: DownloadSettings())
        let resolved = try await resolver.resolve([track], format: format)
        let media = try resolved[0].get()
        #expect(media.format == format)
        #expect(MediaDownloader.isEncrypted(media.urls[0]))

        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "deezdown-test-\(format.apiName).\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: destination) }

        let started = ContinuousClock.now
        let written = try await MediaDownloader().download(media, to: destination)
        let elapsed = ContinuousClock.now - started

        #expect(written == Int64(track.filesize(for: format)))

        let header = try FileHandle(forReadingFrom: destination).read(upToCount: 4)
        #expect(header == (format == .flac ? Data("fLaC".utf8) : Data([0xFF, 0xFB, 0xE0, 0x00])))

        let errors = try ffmpeg("ffmpeg", "-v", "error", "-i", destination.path(percentEncoded: false), "-f", "null", "-")
        #expect(errors.isEmpty, "ffmpeg reported: \(errors)")

        let megabytes = Double(written) / 1_000_000
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("  \(format.apiName): \(Int(megabytes)) MB in \(String(format: "%.2f", seconds))s = \(String(format: "%.1f", megabytes / seconds)) MB/s")
    }

    @Test func `a whole album resolves in two round trips`() async throws {
        try await session.login(arl: #require(liveARL))

        let started = ContinuousClock.now
        let tracks = try await session.albumTracks(id: "302127").map { Track(gateway: $0) }
        let resolver = MediaResolver(session: session, settings: DownloadSettings())
        let resolved = try await resolver.resolve(tracks, format: .flac)
        let elapsed = ContinuousClock.now - started

        #expect(resolved.count == 14)
        #expect(resolved.allSatisfy { if case .success = $0 { true } else { false } })
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("  resolved 14 tracks in \(String(format: "%.2f", seconds))s")
        #expect(seconds < 5)
    }
}

@Suite(.enabled(if: liveARL != nil, "set DEEZDOWN_TEST_ARL to run live Deezer tests"), .serialized)
struct LiveTagging {
    let session = DeezerSession()

    @Test(arguments: [TrackFormat.flac, .mp3_320])
    func `a tagged file keeps decoding and carries its metadata and cover`(format: TrackFormat) async throws {
        try await session.login(arl: #require(liveARL))

        var settings = DownloadSettings()
        settings.tags.lyrics = true
        settings.tags.replayGain = true
        settings.tags.trackTotal = true
        settings.tags.discTotal = true
        settings.tags.explicit = true
        settings.tags.source = true

        let gateway = try await session.trackData(id: "3135556")
        var track = Track(gateway: gateway, album: Album(gateway: try await session.albumData(id: "302127")))
        track.lyrics = Lyrics(results: try await session.lyrics(trackID: "3135556"))
        track = track.applying(settings)

        let resolver = MediaResolver(session: session, settings: settings)
        let media = try (try await resolver.resolve([track], format: format))[0].get()

        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "deezdown-tagged.\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: destination) }
        try await MediaDownloader().download(media, to: destination)

        let artwork = await ArtworkStore().image(track.album.cover, size: 800, format: .jpeg(quality: 90))
        #expect(artwork?.isEmpty == false)
        try Tagger.tag(track, format: format, at: destination, artwork: artwork, settings: settings)

        let errors = try ffmpeg("ffmpeg", "-v", "error", "-i", destination.path(percentEncoded: false), "-f", "null", "-")
        #expect(errors.isEmpty, "ffmpeg reported: \(errors)")

        let tags = ffprobeTags(
            try ffmpeg(
                "ffprobe", "-v", "error", "-show_entries", "format_tags", "-of", "default=nw=1",
                destination.path(percentEncoded: false)
            )
        )
        #expect(tags["title"] == "Harder, Better, Faster, Stronger")
        #expect(tags["album"] == "Discovery")
        #expect(tags["artist"]?.contains("Daft Punk") == true)
        #expect(tags["date"]?.hasPrefix("2001") == true || tags["year"]?.hasPrefix("2001") == true)
        #expect(tags["isrc"] == "GBDUW0000059" || tags["tsrc"] == "GBDUW0000059")
        #expect(tags["publisher"] != nil || tags["label"] != nil)

        let streams = try ffmpeg(
            "ffprobe", "-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0",
            destination.path(percentEncoded: false)
        )
        #expect(streams.contains(format == .flac ? "flac" : "mp3"), "wrong codec: \(streams)")
        #expect(streams.contains("mjpeg") || streams.contains("png"), "no embedded cover: \(streams)")
    }
}

/// `key=value` lines, as ffprobe's `default=nw=1` writes them.
private func ffprobeTags(_ output: String) -> [String: String] {
    output.split(separator: "\n").reduce(into: [:]) { result, line in
        guard let split = line.firstIndex(of: "=") else { return }
        let key = line[line.startIndex..<split].replacing("TAG:", with: "")
        result[key.lowercased()] = String(line[line.index(after: split)...])
    }
}
