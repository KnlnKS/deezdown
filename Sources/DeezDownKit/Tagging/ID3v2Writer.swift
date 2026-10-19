import Foundation

/// Builds an ID3v2.3 tag. Deezer's MP3s arrive untagged, so the tag is simply prepended.
struct ID3v2Writer {
    private var frames: [UInt8] = []

    static let unicodeEncoding: UInt8 = 0x01
    static let latinEncoding: UInt8 = 0x00

    static func unicode(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = [0xFF, 0xFE]
        for unit in text.utf16 {
            bytes.append(UInt8(unit & 0xFF))
            bytes.append(UInt8(unit >> 8))
        }
        return bytes
    }

    static let unicodeTerminator: [UInt8] = [0x00, 0x00]

    mutating func addText(_ identifier: String, _ value: String) {
        guard !value.isEmpty else { return }
        append(identifier, [Self.unicodeEncoding] + Self.unicode(value))
    }

    mutating func addUserText(_ description: String, _ value: String) {
        guard !value.isEmpty else { return }
        append(
            "TXXX",
            [Self.unicodeEncoding] + Self.unicode(description) + Self.unicodeTerminator
                + Self.unicode(value)
        )
    }

    mutating func addUnsyncedLyrics(_ lyrics: String) {
        guard !lyrics.isEmpty else { return }
        append(
            "USLT",
            [Self.unicodeEncoding] + Array("XXX".utf8) + Self.unicode("")
                + Self.unicodeTerminator + Self.unicode(lyrics)
        )
    }

    mutating func addSyncedLyrics(_ lines: [(text: String, milliseconds: Int)]) {
        guard !lines.isEmpty else { return }
        var payload: [UInt8] = [Self.unicodeEncoding]
        payload += Array("XXX".utf8)
        payload += [0x02, 0x01]
        payload += Self.unicode("") + Self.unicodeTerminator
        for line in lines {
            payload += Self.unicode(line.text) + Self.unicodeTerminator
            payload += [UInt8](bigEndian: max(0, line.milliseconds))
        }
        append("SYLT", payload)
    }

    mutating func addInvolvedPeople(_ pairs: [(role: String, person: String)]) {
        guard !pairs.isEmpty else { return }
        var payload: [UInt8] = [Self.unicodeEncoding]
        for pair in pairs {
            payload += Self.unicode(pair.role) + Self.unicodeTerminator
            payload += Self.unicode(pair.person) + Self.unicodeTerminator
        }
        append("IPLS", payload)
    }

    /// The front cover, described as deemix describes it.
    mutating func addPicture(_ image: Data, useUnicode: Bool) {
        var payload = [useUnicode ? Self.unicodeEncoding : Self.latinEncoding]
        payload += Array(ImageDimensions.mimeType(of: image).utf8) + [0x00]
        payload.append(0x03)
        payload += useUnicode ? Self.unicode("cover") + Self.unicodeTerminator : Array("cover".utf8) + [0x00]
        payload += image
        append("APIC", payload)
    }

    /// A rating with no e-mail and no play counter, as deemix writes it.
    mutating func addPopularimeter(rating: UInt8) {
        append("POPM", [0x00, rating])
    }

    private mutating func append(_ identifier: String, _ payload: [UInt8]) {
        frames += Array(identifier.utf8)
        frames += [UInt8](bigEndian: payload.count)
        frames += [0x00, 0x00]
        frames += payload
    }

    func data() -> Data {
        var output: [UInt8] = Array("ID3".utf8) + [0x03, 0x00, 0x00]
        output += Self.synchsafe(frames.count)
        output += frames
        return Data(output)
    }

    static func synchsafe(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F),
        ]
    }

    static func synchsafeValue(_ bytes: [UInt8]) -> Int {
        bytes.reduce(0) { ($0 << 7) | Int($1 & 0x7F) }
    }

}
