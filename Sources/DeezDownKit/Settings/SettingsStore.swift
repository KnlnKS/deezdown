import Foundation

public struct SettingsStore: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    /// Never throws, and never discards settings it does understand: the stored file is merged
    /// onto the defaults, so an old or partial config keeps working. Should the merge not
    /// decode, values are taken one at a time and only those this version cannot read are
    /// dropped.
    public func load() -> DownloadSettings {
        var settings = DownloadSettings()
        if let stored = try? Data(contentsOf: paths.settingsFile),
            let overlay = try? JSONDecoder().decode(JSONValue.self, from: stored),
            let base = try? settings.json()
        {
            if let decoded = DownloadSettings(json: base.merging(overlay)) {
                settings = decoded
            } else {
                var tree = base
                for leaf in overlay.leaves {
                    let candidate = tree.merging(leaf)
                    if let decoded = DownloadSettings(json: candidate) { (tree, settings) = (candidate, decoded) }
                }
            }
        }
        settings.repair()
        return settings
    }

    public func save(_ settings: DownloadSettings) throws {
        var settings = settings
        settings.repair()
        try paths.createConfigDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: paths.settingsFile, options: .atomic)
    }
}

extension DownloadSettings {
    /// The settings as the config file's tree, which a partial config can be merged onto.
    public func json() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self))
    }

    public init?(json: JSONValue) {
        guard let data = try? JSONEncoder().encode(json),
            let settings = try? JSONDecoder().decode(DownloadSettings.self, from: data)
        else { return nil }
        self = settings
    }
}

/// Plain on-disk storage, as specified. Swapping in the Keychain means changing only this type.
public struct CredentialStore: Sendable {
    private struct Login: Codable {
        var arl: String
    }

    public let paths: AppPaths

    public init(paths: AppPaths) {
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
        try paths.createConfigDirectory()
        // The ARL signs in as the account and a portable config may sit anywhere, so the file
        // is only its owner's before the ARL goes in, and replaces the old one whole.
        let file = paths.loginFile.path(percentEncoded: false)
        let staged = file + ".partial"
        guard FileManager.default.createFile(atPath: staged, contents: nil, attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        try JSONEncoder().encode(Login(arl: arl)).write(to: URL(fileURLWithPath: staged))
        guard rename(staged, file) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: paths.loginFile)
    }
}
