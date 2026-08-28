import Foundation

public struct SettingsStore: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    /// Never throws: a corrupt or partial config falls back to defaults rather than blocking launch.
    public func load() -> DownloadSettings {
        var settings: DownloadSettings
        if let data = try? Data(contentsOf: paths.settingsFile),
            let decoded = try? JSONDecoder().decode(DownloadSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = DownloadSettings()
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
