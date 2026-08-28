import Foundation

public enum M3U8Writer {
    /// Paths are written relative to the extras folder so the playlist survives being moved.
    public static func write(files: [URL?], to destination: URL, relativeTo root: URL) throws {
        let prefix = root.path(percentEncoded: false)
        let lines = files.map { file -> String in
            guard let file else { return "" }
            let path = file.path(percentEncoded: false)
            return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count).drop { $0 == "/" }) : path
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try lines.joined(separator: "\n").write(to: destination, atomically: true, encoding: .utf8)
    }
}

public enum LRCWriter {
    public static func write(_ lyrics: Lyrics, to destination: URL, overwrite: Bool) throws {
        let text = lyrics.lrc
        guard !text.isEmpty else { return }
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)), !overwrite {
            return
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }
}

public enum LogWriter {
    public static func append(_ lines: [String], to destination: URL) throws {
        guard !lines.isEmpty else { return }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let text = lines.joined(separator: "\n") + "\n"
        if let handle = try? FileHandle(forWritingTo: destination) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        } else {
            try text.write(to: destination, atomically: true, encoding: .utf8)
        }
    }
}
