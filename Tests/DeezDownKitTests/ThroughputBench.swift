import Foundation
import Testing
@testable import DeezDownKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["DEEZDOWN_BENCH"] != nil))
struct ThroughputBench {
    @Test func `decrypt throughput`() throws {
        let size = 25 << 20
        let input = [UInt8](repeating: 0x5A, count: size)
        let decryptor = try StripeDecryptor(trackID: "3135556")
        let started = ContinuousClock.now
        var total = 0
        for chunk in stride(from: 0, to: size, by: MediaDownloader.readBufferSize) {
            let upper = min(chunk + MediaDownloader.readBufferSize, size)
            total += try decryptor.consume(input[chunk..<upper]).count
        }
        let elapsed = ContinuousClock.now - started
        let seconds = Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds)
        print("  decrypt-only: \(String(format: "%.0f", Double(total) / 1_000_000 / seconds)) MB/s")
    }

    @Test func `byte append throughput`() {
        let size = 25 << 20
        let input = [UInt8](repeating: 0x5A, count: size)
        var buffer = [UInt8]()
        buffer.reserveCapacity(MediaDownloader.readBufferSize)
        var total = 0
        let started = ContinuousClock.now
        for byte in input {
            buffer.append(byte)
            if buffer.count == MediaDownloader.readBufferSize {
                total += buffer.count
                buffer.removeAll(keepingCapacity: true)
            }
        }
        let elapsed = ContinuousClock.now - started
        let seconds = Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds)
        print("  byte-append-only: \(String(format: "%.0f", Double(total) / 1_000_000 / seconds)) MB/s")
    }
}
