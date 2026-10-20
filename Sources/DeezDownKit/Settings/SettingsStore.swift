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
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
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
