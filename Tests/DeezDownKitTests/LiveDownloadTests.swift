import Foundation
import Testing
@testable import DeezDownKit

private let liveARL = ProcessInfo.processInfo.environment["DEEZDOWN_TEST_ARL"]

@discardableResult
private func ffmpegDecodes(_ url: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    process.arguments = ["-v", "error", "-i", url.path(percentEncoded: false), "-f", "null", "-"]
    let pipe = Pipe()
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

        let errors = try ffmpegDecodes(destination)
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

private func ffprobeTags(_ url: URL) throws -> [String: String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
    process.arguments = [
        "-v", "error", "-show_entries", "format_tags", "-of", "default=nw=1",
        url.path(percentEncoded: false),
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return output.split(separator: "\n").reduce(into: [:]) { result, line in
        guard let split = line.firstIndex(of: "=") else { return }
        let key = String(line[line.startIndex..<split]).replacingOccurrences(of: "TAG:", with: "")
        result[key.lowercased()] = String(line[line.index(after: split)...])
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

        let errors = try ffmpegDecodes(destination)
        #expect(errors.isEmpty, "ffmpeg reported: \(errors)")

        let tags = try ffprobeTags(destination)
        #expect(tags["title"] == "Harder, Better, Faster, Stronger")
        #expect(tags["album"] == "Discovery")
        #expect(tags["artist"]?.contains("Daft Punk") == true)
        #expect(tags["date"]?.hasPrefix("2001") == true || tags["year"]?.hasPrefix("2001") == true)
        #expect(tags["isrc"] == "GBDUW0000059" || tags["tsrc"] == "GBDUW0000059")
        #expect(tags["publisher"] != nil || tags["label"] != nil)

        let streams = try ffprobeStreams(destination)
        #expect(streams.contains(format == .flac ? "flac" : "mp3"), "wrong codec: \(streams)")
        #expect(streams.contains("mjpeg") || streams.contains("png"), "no embedded cover: \(streams)")
    }
}

private func ffprobeStreams(_ url: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
    process.arguments = [
        "-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0",
        url.path(percentEncoded: false),
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return output
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["DEEZDOWN_DUMP"] != nil), .serialized)
struct TagDump {
    @Test(arguments: [TrackFormat.flac, .mp3_320])
    func `dump`(format: TrackFormat) async throws {
        let session = DeezerSession()
        try await session.login(arl: #require(liveARL))
        var settings = DownloadSettings()
        settings.tags.lyrics = true
        settings.tags.replayGain = true
        settings.tags.composer = true
        settings.tags.involvedPeople = true
        settings.tags.copyright = true
        settings.tags.trackTotal = true
        settings.tags.discTotal = true
        var track = Track(gateway: try await session.trackData(id: "3135556"),
                          album: Album(gateway: try await session.albumData(id: "302127")))
        track.lyrics = Lyrics(results: try await session.lyrics(trackID: "3135556"))
        track = track.applying(settings)
        let resolver = MediaResolver(session: session, settings: settings)
        let media = try (try await resolver.resolve([track], format: format))[0].get()
        let out = URL(fileURLWithPath: "/tmp/deezdown-dump.\(format.fileExtension)")
        try await MediaDownloader().download(media, to: out)
        let art = await ArtworkStore().image(track.album.cover, size: 800, format: .jpeg(quality: 90))
        try Tagger.tag(track, format: format, at: out, artwork: art, settings: settings)
        print("WROTE \(out.path)")
    }
}
