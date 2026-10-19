import CommonCrypto
import CryptoKit
import Foundation

public enum StripeCrypto {
    public static let blockSize = 2048
    public static let groupSize = 6144

    static let secret = Array("g4el58wc0zvf9na1".utf8)
    static let iv: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7]
    static let hexDigits = Array("0123456789abcdef".utf8)

    public static func blowfishKey(trackID: String) -> [UInt8] {
        let digest = Insecure.MD5.hash(data: Data(trackID.utf8))
        let hex = digest.flatMap { [hexDigits[Int($0 >> 4)], hexDigits[Int($0 & 0x0F)]] }
        return (0..<16).map { hex[$0] ^ hex[$0 + 16] ^ secret[$0] }
    }
}

public struct StripeDecryptError: Error, Sendable {
    public let status: Int32
}

public final class StripeDecryptor {
    private let cryptor: CCCryptorRef
    private var pending: [UInt8] = []
    private var sawFirstBytes = false

    public init(trackID: String) throws {
        let key = StripeCrypto.blowfishKey(trackID: trackID)
        var ref: CCCryptorRef?
        let status = key.withUnsafeBytes { keyBuf in
            StripeCrypto.iv.withUnsafeBytes { ivBuf in
                CCCryptorCreateWithMode(
                    CCOperation(kCCDecrypt),
                    CCMode(kCCModeCBC),
                    CCAlgorithm(kCCAlgorithmBlowfish),
                    CCPadding(ccNoPadding),
                    ivBuf.baseAddress,
                    keyBuf.baseAddress,
                    key.count,
                    nil, 0, 0,
                    CCModeOptions(0),
                    &ref
                )
            }
        }
        guard status == kCCSuccess, let ref else { throw StripeDecryptError(status: status) }
        cryptor = ref
        pending.reserveCapacity(StripeCrypto.groupSize)
    }

    deinit {
        CCCryptorRelease(cryptor)
    }

    public func consume(_ incoming: some Sequence<UInt8>) throws -> [UInt8] {
        pending.append(contentsOf: incoming)
        guard pending.count >= StripeCrypto.groupSize else { return [] }

        let groups = pending.count / StripeCrypto.groupSize
        let taken = groups * StripeCrypto.groupSize
        var out = Array(pending[..<taken])
        pending.removeFirst(taken)

        for index in 0..<groups {
            try decryptBlock(in: &out, at: index * StripeCrypto.groupSize)
        }
        return depadIfNeeded(out)
    }

    public func finish() throws -> [UInt8] {
        var out = pending
        pending.removeAll(keepingCapacity: false)
        if out.count >= StripeCrypto.blockSize {
            try decryptBlock(in: &out, at: 0)
        }
        return depadIfNeeded(out)
    }

    /// CommonCrypto deciphers in place, so the block never leaves the buffer.
    private func decryptBlock(in buffer: inout [UInt8], at offset: Int) throws {
        var status = StripeCrypto.iv.withUnsafeBytes { CCCryptorReset(cryptor, $0.baseAddress) }
        guard status == kCCSuccess else { throw StripeDecryptError(status: status) }

        var moved = 0
        status = buffer.withUnsafeMutableBytes { bytes in
            let block = bytes.baseAddress! + offset
            return CCCryptorUpdate(cryptor, block, StripeCrypto.blockSize, block, StripeCrypto.blockSize, &moved)
        }
        guard status == kCCSuccess, moved == StripeCrypto.blockSize else {
            throw StripeDecryptError(status: status)
        }
    }

    private func depadIfNeeded(_ buffer: [UInt8]) -> [UInt8] {
        guard !sawFirstBytes, !buffer.isEmpty else { return buffer }
        sawFirstBytes = true
        guard buffer[0] == 0 else { return buffer }
        if buffer.count >= 8, Array(buffer[4..<8]) == Array("ftyp".utf8) { return buffer }
        guard let start = buffer.firstIndex(where: { $0 != 0 }) else { return [] }
        return Array(buffer[start...])
    }
}
