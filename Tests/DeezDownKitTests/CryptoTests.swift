import CommonCrypto
import Foundation
import Testing
@testable import DeezDownKit

@Test func `blowfish key matches the vector captured from a live download`() {
    #expect(StripeCrypto.blowfishKey(trackID: "3135556") == Array("llfk9f,7e%u`<d49".utf8))
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
    let plaintext = plaintext(count: size)

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
