import CommonCrypto
import Foundation
@testable import DeezDownKit

private func freshBlowfishCBC(_ block: [UInt8], key: [UInt8]) -> [UInt8] {
    let capacity = block.count
    var output = [UInt8](repeating: 0, count: capacity)
    var moved = 0
    let status = key.withUnsafeBytes { keyBuf in
        StripeCrypto.iv.withUnsafeBytes { ivBuf in
            block.withUnsafeBytes { inBuf in
                output.withUnsafeMutableBytes { outBuf in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmBlowfish),
                        CCOptions(0),
                        keyBuf.baseAddress, key.count,
                        ivBuf.baseAddress,
                        inBuf.baseAddress, capacity,
                        outBuf.baseAddress, capacity,
                        &moved
                    )
                }
            }
        }
    }
    precondition(status == kCCSuccess && moved == capacity)
    return output
}

/// Enciphers a buffer the way Deezer's CDN does: Blowfish CBC over the first of every three
/// 2048-byte blocks, the rest left in the clear.
func stripeEncrypt(_ plaintext: [UInt8], key: [UInt8]) -> [UInt8] {
    var out = plaintext
    var offset = 0
    while offset < plaintext.count {
        let remaining = plaintext.count - offset
        if remaining >= StripeCrypto.blockSize {
            let block = Array(plaintext[offset..<(offset + StripeCrypto.blockSize)])
            out.replaceSubrange(
                offset..<(offset + StripeCrypto.blockSize),
                with: freshBlowfishCBC(block, key: key)
            )
        }
        offset += StripeCrypto.groupSize
    }
    return out
}

/// A FLAC-looking buffer of repeatable bytes.
func plaintext(count: Int) -> [UInt8] {
    var bytes = Array("fLaC".utf8)
    var seed: UInt8 = 1
    while bytes.count < count {
        seed = seed &* 37 &+ 11
        bytes.append(seed)
    }
    return Array(bytes.prefix(count))
}
