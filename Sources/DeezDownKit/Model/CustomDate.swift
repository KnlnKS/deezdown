import Foundation

public struct CustomDate: Sendable, Codable, Equatable, Hashable {
    public var day: String
    public var month: String
    public var year: String

    public init(day: String = "00", month: String = "00", year: String = "XXXX") {
        self.day = day
        self.month = month
        self.year = year
    }

    public init?(deezerString: String?) {
        guard let deezerString, deezerString.count >= 4, !deezerString.hasPrefix("0000") else { return nil }
        let characters = Array(deezerString)
        year = String(characters[0..<4])
        month = characters.count >= 7 ? String(characters[5..<7]) : "00"
        day = characters.count >= 10 ? String(characters[8..<10]) : "00"
        fixDayMonth()
    }

    /// Today in the user's own calendar. Deliberately not a `DateFormatter`: building one
    /// costs more than every other part of preparing a download put together.
    public static var today: CustomDate {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return CustomDate(
            day: String(format: "%02d", parts.day ?? 0),
            month: String(format: "%02d", parts.month ?? 0),
            year: String(parts.year ?? 0)
        )
    }

    public mutating func fixDayMonth() {
        if let numeric = Int(month), numeric > 12 {
            swap(&day, &month)
        }
    }

    public func formatted(_ template: String) -> String {
        var output = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            switch character {
            case "D", "d": output += day
            case "M", "m": output += month
            case "Y", "y": output += year
            default: output.append(character)
            }
            index = template.index(after: index)
            while index < template.endIndex, template[index] == character {
                index = template.index(after: index)
            }
        }
        return output
    }
}
