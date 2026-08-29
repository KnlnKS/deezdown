import Foundation
import Synchronization
import Testing
@testable import DeezDownKit

/// Serves a fixture over `file://` from a directory named `media`, which is what makes the
/// downloader treat the stream as enciphered — the same rule it applies to Deezer's CDN.
private func fixture(_ bytes: [UInt8], named name: String) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "deezdown-\(UUID().uuidString)")
        .appending(path: "media")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: name)
    try Data(bytes).write(to: url)
    return url
}

private func plaintext(count: Int) -> [UInt8] {
    var bytes = Array("fLaC".utf8)
    var seed: UInt8 = 1
    while bytes.count < count {
        seed = seed &* 37 &+ 11
        bytes.append(seed)
    }
    return Array(bytes.prefix(count))
}

@Suite struct DownloadStream {
    let trackID = "3135556"

    @Test(arguments: [StripeCrypto.groupSize * 40 + 991, StripeCrypto.blockSize - 1, 3 << 20])
    func `a streamed download deciphers to the original bytes`(size: Int) async throws {
        let expected = plaintext(count: size)
        let source = try fixture(
            stripeEncrypt(expected, key: StripeCrypto.blowfishKey(trackID: trackID)),
            named: "track.bin"
        )
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        #expect(MediaDownloader.isEncrypted(source))

        let destination = source.deletingLastPathComponent().appending(path: "out.flac")
        let media = ResolvedMedia(
            track: Track(gateway: .object(["SNG_ID": .string(trackID)])), format: .flac, urls: [source]
        )

        let progress = Mutex<[Int64]>([])
        let written = try await MediaDownloader().download(media, to: destination) { done, _ in
            progress.withLock { $0.append(done) }
        }

        #expect(written == Int64(size))
        #expect(try Data(contentsOf: destination) == Data(expected))
        #expect(progress.withLock { $0.last } == Int64(size))
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathExtension("part").path))
    }

    @Test func `a missing stream reports a failure and leaves nothing behind`() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "deezdown-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appending(path: "out.flac")
        let media = ResolvedMedia(
            track: Track(gateway: .object(["SNG_ID": "3135556"])),
            format: .flac,
            urls: [directory.appending(path: "media/absent.bin")]
        )

        await #expect(throws: DownloadFailure.self) {
            try await MediaDownloader().download(media, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
