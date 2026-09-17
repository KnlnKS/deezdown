import ArgumentParser
import DeezDownKit
import Foundation

struct ConfigurationValue {
    private var root: [String: JSONValue]

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

    mutating func setting(_ key: String, to input: String) throws -> DownloadSettings {
        let original = try lookup(key)
        let replacement: JSONValue
        switch original {
        case .bool:
            guard ["true", "false"].contains(input.lowercased()) else {
                throw ValidationError("\(key) expects true or false.")
            }
            replacement = .bool(input.lowercased() == "true")
        case .int:
            guard let number = Int(input) else { throw ValidationError("\(key) expects an integer.") }
            replacement = .int(number)
        case .double:
            guard let number = Double(input), number.isFinite else {
                throw ValidationError("\(key) expects a number.")
            }
            replacement = .double(number)
        case .string:
            replacement = .string(input)
        default:
            throw ValidationError("\(key) cannot be changed with this command.")
        }

        let parts = key.split(separator: ".").map(String.init)
        if parts.count == 1 {
            root[parts[0]] = replacement
        } else {
            var nested = root[parts[0]]!.objectValue
            nested[parts[1]] = replacement
            root[parts[0]] = .object(nested)
        }

        do {
            return try JSONDecoder().decode(DownloadSettings.self, from: JSONEncoder().encode(root))
        } catch {
            throw ValidationError("Invalid value for \(key): \(error.localizedDescription)")
        }
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
