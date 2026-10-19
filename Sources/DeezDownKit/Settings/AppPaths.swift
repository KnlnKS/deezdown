import Foundation

public struct AppPaths: Sendable {
    public let configDirectory: URL

    public var settingsFile: URL { configDirectory.appending(path: "config.json") }
    public var loginFile: URL { configDirectory.appending(path: "login.json") }
    public var queueDirectory: URL { configDirectory.appending(path: "queue") }

    public func createConfigDirectory() throws {
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    }
}

extension AppPaths {
    public init(portable: Bool = false) {
        if portable {
            configDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appending(path: "config")
        } else if let environment = ProcessInfo.processInfo.environment["DEEZDOWN_DATA_DIR"] {
            configDirectory = URL(fileURLWithPath: environment, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            configDirectory = (support ?? URL(fileURLWithPath: NSHomeDirectory()))
                .appending(path: "deezdown")
        }
    }
}
