import ArgumentParser
import DeezDownKit
import Foundation

struct ConfigurationValue {
    private let root: [String: JSONValue]

    init(_ settings: DownloadSettings) throws {
        root = try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(settings))
    }

    func render(key: String?) throws -> String {
        let value: JSONValue
        if let key {
            value = try lookup(key)
        } else {
            value = .object(root)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// The text is read the way a stored config is, and repaired the way it would be saved.
    func setting(_ key: String, to input: String) throws -> DownloadSettings {
        let expected =
            switch try lookup(key) {
            case .bool: "true or false"
            case .int: "an integer"
            case .object: throw ValidationError("\(key) cannot be changed with this command.")
            default: "one of its listed values"
            }
        let overlay = key.split(separator: ".").reversed().reduce(JSONValue.string(input)) { .object([String($1): $0]) }
        guard
            var settings = try? JSONDecoder().decode(
                DownloadSettings.self, from: JSONEncoder().encode(JSONValue.object(root).merging(overlay)))
        else { throw ValidationError("\(key) expects \(expected).") }
        settings.repair()
        return settings
    }

    private func lookup(_ key: String) throws -> JSONValue {
        let parts = key.split(separator: ".").map(String.init)
        guard parts.count == 1 || (parts.count == 2 && parts[0] == "tags"),
              let top = root[parts[0]],
              let value = parts.count == 1 ? top : top.objectValue[parts[1]]
        else { throw ValidationError("Unknown setting \(key). Run `deezdown config get` to list names.") }
        return value
    }
}
