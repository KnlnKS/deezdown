import Foundation

/// Rewrites a FLAC file's metadata blocks, keeping stream structure and dropping prior tags.
enum FLACTagWriter {
    private enum BlockType: UInt8 {
        case streamInfo = 0, padding = 1, application = 2, seekTable = 3
        case vorbisComment = 4, cueSheet = 5, picture = 6
    }

    struct MalformedFLAC: Error {}

    static func write(comments: [(String, String)], picture: Data?, to url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }

        guard let magic = try handle.read(upToCount: 4), magic == Data("fLaC".utf8) else {
            throw MalformedFLAC()
        }

        var preserved: [(UInt8, Data)] = []
        var audioOffset: UInt64 = 4
        while true {
            guard let header = try handle.read(upToCount: 4), header.count == 4 else { throw MalformedFLAC() }
            let bytes = [UInt8](header)
            let isLast = bytes[0] & 0x80 != 0
            let type = bytes[0] & 0x7F
            let length = Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
            let body = try handle.read(upToCount: length) ?? Data()
            guard body.count == length else { throw MalformedFLAC() }

            if [BlockType.streamInfo, .seekTable, .cueSheet].contains(where: { $0.rawValue == type }) {
                preserved.append((type, body))
            }
            audioOffset = handle.offsetInFile
            if isLast { break }
        }

        var blocks: [(UInt8, Data)] = preserved
        blocks.append((BlockType.vorbisComment.rawValue, vorbisCommentBlock(comments)))
        if let picture { blocks.append((BlockType.picture.rawValue, pictureBlock(picture))) }

        var header = Data("fLaC".utf8)
        for (index, block) in blocks.enumerated() {
            let isLast = index == blocks.count - 1
            header.append(block.0 | (isLast ? 0x80 : 0x00))
            let length = block.1.count
            header.append(contentsOf: [
                UInt8(truncatingIfNeeded: length >> 16), UInt8(truncatingIfNeeded: length >> 8),
                UInt8(truncatingIfNeeded: length),
            ])
            header.append(block.1)
        }

        try TagRewriter.rewrite(url, reading: handle, header: header, audioFrom: audioOffset)
    }

    private static func littleEndian(_ value: Int) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 24),
        ]
    }

    private static func bigEndian(_ value: Int) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value),
        ]
    }

    static func vorbisCommentBlock(_ comments: [(String, String)]) -> Data {
        let vendor = Array("deezdown".utf8)
        var bytes = littleEndian(vendor.count) + vendor
        bytes += littleEndian(comments.count)
        for (field, value) in comments {
            let entry = Array("\(field)=\(value)".utf8)
            bytes += littleEndian(entry.count) + entry
        }
        return Data(bytes)
    }

    /// The front cover, described as deemix describes it.
    static func pictureBlock(_ picture: Data) -> Data {
        let dimensions = ImageDimensions.read(picture) ?? (0, 0, 24)
        let mime = Array(ImageDimensions.mimeType(of: picture).utf8)
        let description = Array("cover".utf8)
        var bytes = bigEndian(3)
        bytes += bigEndian(mime.count) + mime
        bytes += bigEndian(description.count) + description
        bytes += bigEndian(dimensions.width)
        bytes += bigEndian(dimensions.height)
        bytes += bigEndian(dimensions.depth)
        bytes += bigEndian(0)
        bytes += bigEndian(picture.count)
        return Data(bytes) + picture
    }
}
