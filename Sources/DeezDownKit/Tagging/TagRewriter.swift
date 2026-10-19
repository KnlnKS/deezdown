import Foundation

/// Both tag writers finish the same way: put a new header in front of the audio that is
/// already on disk and swap the file in, without ever holding the audio in memory.
enum TagRewriter {
    static func rewrite(
        _ url: URL,
        reading source: FileHandle,
        header: Data,
        audioFrom start: UInt64,
        audioTo end: UInt64? = nil,
        trailer: Data = Data()
    ) throws {
        let rewritten = url.appendingPathExtension("retag")
        let manager = FileManager.default
        guard manager.createFile(atPath: rewritten.path(percentEncoded: false), contents: header) else {
            throw DownloadFailure(.tagging("could not create the tagged file"))
        }

        let output = try FileHandle(forWritingTo: rewritten)
        try output.seekToEnd()
        try source.seek(toOffset: start)

        var remaining = end.map { Int($0 - start) } ?? .max
        while remaining > 0, let chunk = try source.read(upToCount: min(remaining, 1 << 20)), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
            remaining -= chunk.count
        }
        if !trailer.isEmpty { try output.write(contentsOf: trailer) }
        try output.close()

        _ = try manager.replaceItemAt(url, withItemAt: rewritten)
    }
}

extension [UInt8] {
    /// The low `count` bytes of `value`, most significant first.
    init(bigEndian value: Int, count: Int = 4) {
        self = (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }

    /// The low four bytes of `value`, least significant first.
    init(littleEndian value: Int) {
        self = (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
}
