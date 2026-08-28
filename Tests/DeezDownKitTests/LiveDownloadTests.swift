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
