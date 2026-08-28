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

    mutating func addText(_ identifier: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        append(identifier, [Self.unicodeEncoding] + Self.unicode(value))
    }

    mutating func addUserText(_ description: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        append(
            "TXXX",
            [Self.unicodeEncoding] + Self.unicode(description) + Self.unicodeTerminator
                + Self.unicode(value)
        )
    }

    mutating func addUnsyncedLyrics(_ lyrics: String, language: String = "XXX") {
        guard !lyrics.isEmpty else { return }
        append(
            "USLT",
            [Self.unicodeEncoding] + Array(language.utf8.prefix(3)) + Self.unicode("")
                + Self.unicodeTerminator + Self.unicode(lyrics)
        )
    }

    mutating func addSyncedLyrics(_ lines: [(text: String, milliseconds: Int)], language: String = "XXX") {
        guard !lines.isEmpty else { return }
        var payload: [UInt8] = [Self.unicodeEncoding]
        payload += Array(language.utf8.prefix(3))
        payload += [0x02, 0x01]
        payload += Self.unicode("") + Self.unicodeTerminator
        for line in lines {
            payload += Self.unicode(line.text) + Self.unicodeTerminator
            let stamp = UInt32(max(0, line.milliseconds))
            payload += [
                UInt8(truncatingIfNeeded: stamp >> 24), UInt8(truncatingIfNeeded: stamp >> 16),
                UInt8(truncatingIfNeeded: stamp >> 8), UInt8(truncatingIfNeeded: stamp),
            ]
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

    mutating func addPicture(_ image: Data, mimeType: String, description: String, useUnicode: Bool) {
        guard !image.isEmpty else { return }
        var payload: [UInt8] = []
        if useUnicode {
            payload.append(Self.unicodeEncoding)
            payload += Array(mimeType.utf8) + [0x00]
            payload.append(0x03)
            payload += Self.unicode(description) + Self.unicodeTerminator
        } else {
            payload.append(Self.latinEncoding)
            payload += Array(mimeType.utf8) + [0x00]
            payload.append(0x03)
            payload += Array(description.utf8) + [0x00]
        }
        payload += image
        append("APIC", payload)
    }

    private mutating func append(_ identifier: String, _ payload: [UInt8]) {
        frames += Array(identifier.utf8)
        let size = UInt32(payload.count)
        frames += [
            UInt8(truncatingIfNeeded: size >> 24), UInt8(truncatingIfNeeded: size >> 16),
            UInt8(truncatingIfNeeded: size >> 8), UInt8(truncatingIfNeeded: size),
        ]
        frames += [0x00, 0x00]
        frames += payload
    }

    var isEmpty: Bool { frames.isEmpty }

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

    static func mimeType(for image: Data) -> String {
        image.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
    }
}
