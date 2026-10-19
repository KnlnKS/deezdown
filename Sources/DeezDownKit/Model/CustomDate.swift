import Foundation

public struct CustomDate: Sendable, Equatable, Hashable {
    public var day: String
    public var month: String
    public var year: String
}

extension CustomDate {
    public init?(deezerString: String?) {
        guard let deezerString, deezerString.count >= 4, !deezerString.hasPrefix("0000") else { return nil }
        let characters = Array(deezerString)
        year = String(characters[0..<4])
        month = characters.count >= 7 ? String(characters[5..<7]) : "00"
        day = characters.count >= 10 ? String(characters[8..<10]) : "00"
        if let numeric = Int(month), numeric > 12 { swap(&day, &month) }
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

    /// As in deemix, each run of D, M or Y stands for the day, month or year.
    public func formatted(_ template: String) -> String {
        var output = ""
        var previous: Character?
        for character in template {
            let value: String? =
                switch character {
                case "D": day
                case "M": month
                case "Y": year
                default: nil
                }
            if let value {
                if character != previous { output += value }
            } else {
                output.append(character)
            }
            previous = character
        }
        return output
    }
}
