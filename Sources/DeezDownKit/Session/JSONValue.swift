import Foundation

public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue {
    public subscript(key: String) -> JSONValue {
        if case .object(let dictionary) = self { return dictionary[key] ?? .null }
        return .null
    }

    public subscript(index: Int) -> JSONValue {
        if case .array(let values) = self, values.indices.contains(index) { return values[index] }
        return .null
    }

    public var stringValue: String? {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): value ? "1" : "0"
        default: nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .int(let value): value
        case .double(let value): Int(exactly: value.rounded(.towardZero))
        case .string(let value): Int(value) ?? Double(value).flatMap { Int(exactly: $0.rounded(.towardZero)) }
        case .bool(let value): value ? 1 : 0
        default: nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): value
        case .int(let value): value != 0
        case .string(let value): ["1", "true", "yes"].contains(value.lowercased())
        default: nil
        }
    }

    public var arrayValue: [JSONValue] {
        if case .array(let values) = self { return values }
        return []
    }

    public var objectValue: [String: JSONValue] {
        if case .object(let dictionary) = self { return dictionary }
        return [:]
    }

    public var isEmpty: Bool {
        switch self {
        case .null: true
        case .array(let values): values.isEmpty
        case .object(let dictionary): dictionary.isEmpty
        case .string(let value): value.isEmpty
        default: false
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue {
    /// Overlays `other` on top of `self`, recursing into nested objects so a stored config
    /// that predates a new setting keeps every value it does know about. A scalar takes the
    /// type of the one it replaces where it converts cleanly, since deemix writes some
    /// numbers as strings.
    public func merging(_ other: JSONValue) -> JSONValue {
        switch (self, other) {
        case (.object(let base), .object(let overlay)):
            .object(base.merging(overlay.map { key, value in (key, base[key]?.merging(value) ?? value) }) { $1 })
        case (.int, .string(let text)): Int(text).map(JSONValue.int) ?? other
        case (.double, .string(let text)): Double(text).map(JSONValue.double) ?? other
        case (.double, .int(let number)): .double(Double(number))
        case (.bool, .string(let text)) where ["true", "false"].contains(text.lowercased()):
            .bool(text.lowercased() == "true")
        case (.string, .int(let number)): .string(String(number))
        default: other
        }
    }

    /// Each leaf of an object tree on its own, wrapped back in its path.
    var leaves: [JSONValue] {
        guard case .object(let fields) = self, !fields.isEmpty else { return [self] }
        return fields.flatMap { key, value in value.leaves.map { .object([key: $0]) } }
    }

    /// A gateway record is explicit when the status under its content key says so, or, lacking
    /// one, when its fallback flag does.
    func isExplicit(_ content: String, else fallback: String? = nil) -> Bool {
        (self[content]["EXPLICIT_LYRICS_STATUS"].intValue ?? fallback.flatMap { self[$0].intValue }) == 1
    }
}
