import Foundation
import Testing
@testable import DeezDownKit

@Test func `cover dimensions are read from png and jpeg headers, slice or not`() throws {
    var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    png += Data([0, 0, 0, 0x0D]) + Data("IHDR".utf8)
    png += Data([0, 0, 0x03, 0x20]) + Data([0, 0, 0x02, 0x58])  // 800 x 600
    png += Data([0x08, 0x02])  // 8 bits, truecolour
    #expect(ImageDimensions.read(png).map { [$0.width, $0.height, $0.depth] } == [800, 600, 24])

    var jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) + Data(repeating: 0, count: 14)
    jpeg += Data([0xFF, 0xC0, 0x00, 0x11, 0x08])
    jpeg += Data([0x02, 0x58, 0x03, 0x20, 0x03])  // 600 high, 800 wide, three components
    #expect(ImageDimensions.read(jpeg).map { [$0.width, $0.height, $0.depth] } == [800, 600, 24])

    let padded = (Data(repeating: 0xAB, count: 32) + jpeg).dropFirst(32)
    #expect(ImageDimensions.read(padded).map(\.width) == 800)

    #expect(ImageDimensions.read(Data([0x00, 0x01, 0x02])) == nil)
}
