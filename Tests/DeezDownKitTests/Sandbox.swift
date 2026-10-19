import Foundation

/// A folder of a test's own, removed when the test lets go of it.
struct Sandbox: ~Copyable {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "deezdown-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// Writes a file at a path inside the sandbox, making any folders on the way.
    @discardableResult
    func write(_ data: Data, to path: String) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }
}
