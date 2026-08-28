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
        case .double(let value): Int(value)
        case .string(let value): Int(value) ?? Int(Double(value) ?? .nan)
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
