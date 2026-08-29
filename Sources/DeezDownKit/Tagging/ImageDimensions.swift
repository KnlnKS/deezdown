import Foundation

enum ImageDimensions {
    static func read(_ data: Data) -> (width: Int, height: Int, depth: Int)? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return png(data) }
        if data.starts(with: [0xFF, 0xD8]) { return jpeg(data) }
        return nil
    }

    private static func png(_ data: Data) -> (Int, Int, Int)? {
        guard data.count >= 26 else { return nil }
        let bytes = [UInt8](data.prefix(26))
        let width = bytes[16...19].reduce(0) { $0 << 8 | Int($1) }
        let height = bytes[20...23].reduce(0) { $0 << 8 | Int($1) }
        let bitDepth = Int(bytes[24])
        let channels =
            switch bytes[25] {
            case 0: 1
            case 2: 3
            case 3: 1
            case 4: 2
            default: 4
            }
        return (width, height, bitDepth * channels)
    }

    /// Scans the markers in place: cover art runs to megabytes and only the frame header
    /// near the front is ever read.
    private static func jpeg(_ data: Data) -> (Int, Int, Int)? {
        let bytes = data[data.startIndex...]
        var index = bytes.startIndex + 2
        while index + 9 < bytes.endIndex {
            guard bytes[index] == 0xFF else {
                index += 1
                continue
            }
            let marker = bytes[index + 1]
            if (0xC0...0xCF).contains(marker), ![0xC4, 0xC8, 0xCC].contains(marker) {
                let height = Int(bytes[index + 5]) << 8 | Int(bytes[index + 6])
                let width = Int(bytes[index + 7]) << 8 | Int(bytes[index + 8])
                let depth = Int(bytes[index + 4]) * Int(bytes[index + 9])
                return (width, height, depth)
            }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            index += 2 + max(length, 2)
        }
        return nil
    }
}
