import Foundation
import Testing
@testable import DeezDownKit

@Test func `overwrite modes decide correctly when the file already exists`() throws {
    let sandbox = try Sandbox()
    try sandbox.write(Data(count: 16), to: "song.mp3")
    let base = sandbox.root.appending(path: "song")

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
    try sandbox.write(Data(count: 128_000 / 8 * 200), to: "song.mp3")
    let base = sandbox.root.appending(path: "song")

    #expect(
        OverwritePolicy.decide(base: base, format: .mp3_320, duration: 200, mode: .upgradeBitrate)
            == .download(base.appendingPathExtension("mp3")))
    #expect(
        OverwritePolicy.decide(base: base, format: .mp3_128, duration: 200, mode: .upgradeBitrate)
            == .skip(base.appendingPathExtension("mp3")))
}

@Test func `nothing on disk always means download`() throws {
    let sandbox = try Sandbox()
    let base = sandbox.root.appending(path: "song")
    for mode in OverwriteMode.allCases {
        #expect(
            OverwritePolicy.decide(base: base, format: .flac, duration: 200, mode: mode)
                == .download(base.appendingPathExtension("flac")))
    }
}
