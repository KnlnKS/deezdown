import Foundation
import Testing
@testable import DeezDownKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["DEEZDOWN_BENCH"] != nil))
struct ThroughputBench {
    @Test func `decrypt throughput`() throws {
        let size = 25 << 20
        let chunkSize = 1 << 16
        let input = [UInt8](repeating: 0x5A, count: size)
        let decryptor = try StripeDecryptor(trackID: "3135556")
        let started = ContinuousClock.now
        var total = 0
        for chunk in stride(from: 0, to: size, by: chunkSize) {
            total += try decryptor.consume(input[chunk..<min(chunk + chunkSize, size)]).count
        }
        let elapsed = ContinuousClock.now - started
        let seconds = Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds)
        print("  decrypt-only: \(String(format: "%.0f", Double(total) / 1_000_000 / seconds)) MB/s")
    }
}
