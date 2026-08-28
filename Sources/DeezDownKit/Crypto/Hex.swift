import Foundation

enum Hex {
    static let lowercase = Array("0123456789abcdef".utf8)

    static func encode(_ bytes: some Sequence<UInt8>) -> String {
        var out = [UInt8]()
        for byte in bytes {
            out.append(lowercase[Int(byte >> 4)])
            out.append(lowercase[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func encodeBytes(_ bytes: some Sequence<UInt8>) -> [UInt8] {
        var out = [UInt8]()
        for byte in bytes {
            out.append(lowercase[Int(byte >> 4)])
            out.append(lowercase[Int(byte & 0x0F)])
        }
        return out
    }
}
