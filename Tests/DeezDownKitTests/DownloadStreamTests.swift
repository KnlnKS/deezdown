import Foundation
import Synchronization
import Testing
@testable import DeezDownKit

@Suite struct DownloadStream {
    let trackID = "3135556"

    @Test(arguments: [StripeCrypto.groupSize * 40 + 991, 3 << 20])
    func `a streamed download deciphers to the original bytes`(size: Int) async throws {
        let expected = plaintext(count: size)
        let sandbox = try Sandbox()
        // Served from a folder named `media`, the downloader deciphers it as it would Deezer's CDN.
        let source = try sandbox.write(
            Data(stripeEncrypt(expected, key: StripeCrypto.blowfishKey(trackID: trackID))), to: "media/track.bin"
        )
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
        let sandbox = try Sandbox()
        let destination = sandbox.root.appending(path: "out.flac")
        let media = ResolvedMedia(
            track: Track(gateway: .object(["SNG_ID": "3135556"])),
            format: .flac,
            urls: [sandbox.root.appending(path: "media/absent.bin")]
        )

        await #expect(throws: DownloadFailure.self) {
            try await MediaDownloader().download(media, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
