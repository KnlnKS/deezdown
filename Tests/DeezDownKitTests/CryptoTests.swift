import CommonCrypto
import Foundation
import Testing
@testable import DeezDownKit

private func freshBlowfishCBC(_ block: [UInt8], key: [UInt8], operation: Int) -> [UInt8] {
    let capacity = block.count
    var output = [UInt8](repeating: 0, count: capacity)
    var moved = 0
    let status = key.withUnsafeBytes { keyBuf in
        StripeCrypto.iv.withUnsafeBytes { ivBuf in
            block.withUnsafeBytes { inBuf in
                output.withUnsafeMutableBytes { outBuf in
                    CCCrypt(
                        CCOperation(operation),
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

private func stripeEncrypt(_ plaintext: [UInt8], key: [UInt8]) -> [UInt8] {
    var out = plaintext
    var offset = 0
    while offset < plaintext.count {
        let remaining = plaintext.count - offset
        if remaining >= StripeCrypto.blockSize {
            let block = Array(plaintext[offset..<(offset + StripeCrypto.blockSize)])
            out.replaceSubrange(
                offset..<(offset + StripeCrypto.blockSize),
                with: freshBlowfishCBC(block, key: key, operation: kCCEncrypt)
            )
        }
        offset += StripeCrypto.groupSize
    }
    return out
}

@Test func `blowfish key matches the vector captured from a live download`() {
    #expect(Hex.encode(StripeCrypto.blowfishKey(trackID: "3135556")) == "6c6c666b39662c37652575603c643439")
}

@Test(arguments: [
    StripeCrypto.groupSize * 3,
    StripeCrypto.groupSize * 2 + StripeCrypto.blockSize,
    StripeCrypto.groupSize * 2 + StripeCrypto.blockSize + 501,
    StripeCrypto.groupSize + 7,
    StripeCrypto.blockSize - 1,
])
func `a reset cryptor decrypts identically to a fresh cryptor per block`(size: Int) throws {
    let key = StripeCrypto.blowfishKey(trackID: "3135556")
    var plaintext = Array("fLaC".utf8)
    var seed: UInt8 = 1
    while plaintext.count < size {
        seed = seed &* 37 &+ 11
        plaintext.append(seed)
    }
    plaintext = Array(plaintext.prefix(size))

    let ciphertext = stripeEncrypt(plaintext, key: key)
    let decryptor = try StripeDecryptor(trackID: "3135556")

    var recovered = [UInt8]()
    for chunk in stride(from: 0, to: ciphertext.count, by: 1337) {
        let upper = min(chunk + 1337, ciphertext.count)
        recovered += try decryptor.consume(ciphertext[chunk..<upper])
    }
    recovered += try decryptor.finish()

    #expect(recovered == plaintext)
}

@Test func `the depadder strips leading zeros but spares mp4 ftyp headers`() throws {
    let key = StripeCrypto.blowfishKey(trackID: "3135556")

    var padded = [UInt8](repeating: 0, count: 5) + Array("fLaC".utf8)
    padded += [UInt8](repeating: 0x11, count: StripeCrypto.blockSize - padded.count)
    let strippedDecryptor = try StripeDecryptor(trackID: "3135556")
    var stripped = try strippedDecryptor.consume(stripeEncrypt(padded, key: key))
    stripped += try strippedDecryptor.finish()
    #expect(Array(stripped.prefix(4)) == Array("fLaC".utf8))

    var mp4 = [UInt8]([0, 0, 0, 0x20]) + Array("ftyp".utf8)
    mp4 += [UInt8](repeating: 0x22, count: StripeCrypto.blockSize - mp4.count)
    let keptDecryptor = try StripeDecryptor(trackID: "3135556")
    var kept = try keptDecryptor.consume(stripeEncrypt(mp4, key: key))
    kept += try keptDecryptor.finish()
    #expect(kept == mp4)
}

@Test func `the legacy stream path pads to a whole block, adding sixteen dots when already aligned`() throws {
    let path = try #require(
        LegacyStreamURL.streamPath(
            trackID: "3135556",
            md5Origin: "000790eceb6cb6732d225c0585632b31",
            mediaVersion: "3",
            format: .flac
        )
    )
    #expect(path.count % 32 == 0)

    var payload = Array("000790eceb6cb6732d225c0585632b31".utf8)
    payload.append(LegacyStreamURL.separator)
    payload += Array("9".utf8)
    payload.append(LegacyStreamURL.separator)
    payload += Array("3135556".utf8)
    payload.append(LegacyStreamURL.separator)
    payload += Array("3".utf8)

    let unpadded = 32 + 1 + payload.count + 1
    let expectedDots = 16 - (unpadded % 16)
    #expect(expectedDots >= 1 && expectedDots <= 16)
    #expect(path.count / 2 == unpadded + expectedDots)
}

@Test func `bitrate aliases resolve the way the deemix cli resolves them`() {
    #expect(TrackFormat.parse("flac") == .flac)
    #expect(TrackFormat.parse("lossless") == .flac)
    #expect(TrackFormat.parse("320") == .mp3_320)
    #expect(TrackFormat.parse("mp3") == .mp3_320)
    #expect(TrackFormat.parse("128") == .mp3_128)
    #expect(TrackFormat.parse("360") == .mp4ra3)
    #expect(TrackFormat.parse("360_lq") == .mp4ra1)
    #expect(TrackFormat.parse("nonsense") == nil)
}
