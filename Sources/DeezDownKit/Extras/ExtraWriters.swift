import Foundation

public enum M3U8Writer {
    /// Paths are written relative to the extras folder so the playlist survives being moved.
    public static func write(files: [URL?], to destination: URL, relativeTo root: URL) throws {
        let lines = files.map { $0.map { relativePath(of: $0, in: root) } ?? "" }
        try lines.joined(separator: "\n").writeCreatingFolder(to: destination)
    }

    static func relativePath(of file: URL, in root: URL) -> String {
        let prefix = root.path(percentEncoded: false)
        let path = file.path(percentEncoded: false)
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count).drop { $0 == "/" }) : path
    }
}

/// deemix's executeCommand: the command runs through the shell with %folder% and %filename%
/// quoted, and the download is not finished until it exits.
public enum PostCommand {
    public static func run(_ template: String, folder: URL, filename: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            template
                .replacingOccurrences(of: "%folder%", with: quoted(folder.path(percentEncoded: false)))
                .replacingOccurrences(of: "%filename%", with: quoted(filename)),
        ]
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume() }
        }
    }

    static func quoted(_ text: String) -> String {
        text.isEmpty ? "" : "'" + text.replacingOccurrences(of: "'", with: #"'"'"'"#) + "'"
    }
}

public enum LRCWriter {
    public static func write(_ lyrics: Lyrics, to destination: URL, overwrite: Bool) throws {
        let text = lyrics.lrc
        guard !text.isEmpty else { return }
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)), !overwrite {
            return
        }
        try text.writeCreatingFolder(to: destination)
    }
}

public enum LogWriter {
    /// A collection's log is written whole, with deemix's Windows line endings.
    public static func write(_ lines: [String], to destination: URL) throws {
        try lines.map { $0 + "\r\n" }.joined().writeCreatingFolder(to: destination)
    }

    /// A single download adds its line to the folder's log, once.
    public static func appendOnce(_ line: String, to destination: URL) throws {
        let existing = (try? String(contentsOf: destination, encoding: .utf8)) ?? ""
        guard !existing.contains(line) else { return }
        try (existing + line + "\r\n").write(to: destination, atomically: true, encoding: .utf8)
    }
}

extension String {
    fileprivate func writeCreatingFolder(to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(to: destination, atomically: true, encoding: .utf8)
    }
}
