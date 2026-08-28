import Foundation

public struct SettingsStore: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    /// Never throws, and never discards settings it does understand: the stored file is merged
    /// onto the defaults key by key, so an old or partial config keeps working.
    public func load() -> DownloadSettings {
        var settings = DownloadSettings()
        if let stored = try? Data(contentsOf: paths.settingsFile),
            let overlay = try? JSONDecoder().decode(JSONValue.self, from: stored),
            let defaults = try? JSONEncoder().encode(settings),
            let base = try? JSONDecoder().decode(JSONValue.self, from: defaults),
            let merged = try? JSONEncoder().encode(base.merging(overlay)),
            let decoded = try? JSONDecoder().decode(DownloadSettings.self, from: merged)
        {
            settings = decoded
        }
        settings.repair()
        return settings
    }

    public func save(_ settings: DownloadSettings) throws {
        var settings = settings
        settings.repair()
        try paths.createDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: paths.settingsFile, options: .atomic)
    }
}

/// Plain on-disk storage, as specified. Swapping in the Keychain means changing only this type.
public struct CredentialStore: Sendable {
    private struct Login: Codable {
        var arl: String
    }

    public let paths: AppPaths

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    public func arl() -> String? {
        guard let data = try? Data(contentsOf: paths.loginFile),
            let login = try? JSONDecoder().decode(Login.self, from: data),
            !login.arl.isEmpty
        else { return nil }
        return login.arl
    }

    public func save(arl: String) throws {
        try paths.createDirectories()
        try JSONEncoder().encode(Login(arl: arl)).write(to: paths.loginFile, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: paths.loginFile)
    }
}
