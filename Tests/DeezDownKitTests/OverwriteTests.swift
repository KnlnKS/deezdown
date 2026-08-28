import Foundation
import Testing
@testable import DeezDownKit

private struct Sandbox: ~Copyable {
    let root: URL
    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "deezdown-ow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func make(_ name: String, bytes: Int = 16) throws -> URL {
        let url = root.appending(path: name)
        try Data(repeating: 0, count: bytes).write(to: url)
        return url
    }
    var base: URL { root.appending(path: "song") }
    deinit { try? FileManager.default.removeItem(at: root) }
}

@Test func `overwrite modes decide correctly when the file already exists`() throws {
    let sandbox = try Sandbox()
    _ = try sandbox.make("song.mp3")
    let base = sandbox.base

    #expect(
        OverwritePolicy.decide(base: base, format: .mp3_320, duration: 200, mode: .overwrite)
            == .download(base.appendingPathExtension("mp3")))
    #expect(
        OverwritePolicy.decide(base: base, format: .mp3_320, duration: 200, mode: .skip)
            == .skip(base.appendingPathExtension("mp3")))
    #expect(
        OverwritePolicy.decide(base: base, format: .mp3_320, duration: 200, mode: .tagsOnly)
            == .tagOnly(base.appendingPathExtension("mp3")))
    #expect(
        OverwritePolicy.decide(base: base, format: .mp3_320, duration: 200, mode: .keepBoth)
            == .download(sandbox.root.appending(path: "song (1).mp3")))
    #expect(
        OverwritePolicy.decide(base: base, format: .flac, duration: 200, mode: .skipAnyExtension)
            == .skip(base.appendingPathExtension("mp3")))
    #expect(
        OverwritePolicy.decide(base: base, format: .flac, duration: 200, mode: .skip)
            == .download(base.appendingPathExtension("flac")))
}

@Test func `a low bitrate file is replaced only when upgrading to 320`() throws {
    let sandbox = try Sandbox()
    _ = try sandbox.make("song.mp3", bytes: 128_000 / 8 * 200)
    let base = sandbox.base

    #expect(
        OverwritePolicy.decide(base: base, format: .mp3_320, duration: 200, mode: .upgradeBitrate)
            == .download(base.appendingPathExtension("mp3")))
    #expect(
        OverwritePolicy.decide(base: base, format: .mp3_128, duration: 200, mode: .upgradeBitrate)
            == .skip(base.appendingPathExtension("mp3")))
}

@Test func `nothing on disk always means download`() throws {
    let sandbox = try Sandbox()
    for mode in OverwriteMode.allCases {
        #expect(
            OverwritePolicy.decide(base: sandbox.base, format: .flac, duration: 200, mode: mode)
                == .download(sandbox.base.appendingPathExtension("flac")))
    }
}
