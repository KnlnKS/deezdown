import Foundation
import Observation

/// Browsing data changes slowly, so a tab switch reuses what was already fetched.
@Observable
final class LibraryCache {
    static let lifetime: Duration = .seconds(600)

    private struct Entry {
        var value: Any
        var storedAt: ContinuousClock.Instant
    }

    private var entries: [String: Entry] = [:]

    func value<Value>(_ key: String, as type: Value.Type = Value.self) -> Value? {
        guard let entry = entries[key], ContinuousClock.now - entry.storedAt < Self.lifetime else {
            return nil
        }
        return entry.value as? Value
    }

    func store(_ value: some Any, for key: String) {
        entries[key] = Entry(value: value, storedAt: .now)
    }

    func invalidate(_ key: String? = nil) {
        if let key { entries[key] = nil } else { entries.removeAll() }
    }
}
