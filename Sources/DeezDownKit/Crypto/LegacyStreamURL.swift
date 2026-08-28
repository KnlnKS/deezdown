import CommonCrypto
import CryptoKit
import Foundation

public enum LegacyStreamURL {
    static let separator: UInt8 = 0xA4
    static let aesKey = Array("jo6aey6haid2Teih".utf8)

    public static func streamPath(
        trackID: String,
        md5Origin: String,
        mediaVersion: String,
        format: TrackFormat
    ) -> String? {
        var payload = Array(md5Origin.utf8)
        payload.append(separator)
        payload.append(contentsOf: Array(String(format.rawValue).utf8))
        payload.append(separator)
        payload.append(contentsOf: Array(trackID.utf8))
        payload.append(separator)
        payload.append(contentsOf: Array(mediaVersion.utf8))

        var step = Hex.encodeBytes(Insecure.MD5.hash(data: Data(payload)))
        step.append(separator)
        step.append(contentsOf: payload)
        step.append(separator)
        step.append(contentsOf: [UInt8](repeating: 0x2E, count: 16 - (step.count % 16)))

        guard let encrypted = aesECBEncrypt(step) else { return nil }
        return Hex.encode(encrypted)
    }

    public static func cryptedURL(
        trackID: String,
        md5Origin: String,
        mediaVersion: String,
        format: TrackFormat
    ) -> URL? {
        guard let shard = md5Origin.first,
              let path = streamPath(
                  trackID: trackID,
                  md5Origin: md5Origin,
                  mediaVersion: mediaVersion,
                  format: format
              )
        else { return nil }
        return URL(string: "https://e-cdns-proxy-\(shard).dzcdn.net/mobile/1/\(path)")
    }

    static func aesECBEncrypt(_ input: [UInt8]) -> [UInt8]? {
        let capacity = input.count
        var output = [UInt8](repeating: 0, count: capacity)
        var moved = 0
        let status = aesKey.withUnsafeBytes { keyBuf in
            input.withUnsafeBytes { inBuf in
                output.withUnsafeMutableBytes { outBuf in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBuf.baseAddress, kCCKeySizeAES128,
                        nil,
                        inBuf.baseAddress, input.count,
                        outBuf.baseAddress, capacity,
                        &moved
                    )
                }
            }
        }
        guard status == kCCSuccess, moved == input.count else { return nil }
        return output
    }
}

extension LegacyStreamURL {
    /// Decodes a stream path back into its parts. Used to prove the encoding is correct
    /// now that Deezer has retired the legacy `*-proxy-*.dzcdn.net` hosts entirely.
    static func decodeStreamPath(_ hex: String) -> [String]? {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        guard let plain = aesECBDecrypt(bytes) else { return nil }
        return plain.split(separator: separator, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    static func aesECBDecrypt(_ input: [UInt8]) -> [UInt8]? {
        let capacity = input.count
        var output = [UInt8](repeating: 0, count: capacity)
        var moved = 0
        let status = aesKey.withUnsafeBytes { keyBuf in
            input.withUnsafeBytes { inBuf in
                output.withUnsafeMutableBytes { outBuf in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBuf.baseAddress, kCCKeySizeAES128,
                        nil,
                        inBuf.baseAddress, capacity,
                        outBuf.baseAddress, capacity,
                        &moved
                    )
                }
            }
        }
        guard status == kCCSuccess, moved == capacity else { return nil }
        return output
    }
}
