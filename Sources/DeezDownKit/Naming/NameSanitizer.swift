import Foundation

public enum NameSanitizer {
    static let illegal: Set<Character> = ["\0", "/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
    public static let segmentLimit = 200

    /// Deezer titles routinely contain characters HFS+/APFS or Finder will not accept.
    public static func fixName(_ name: String, replacer: String) -> String {
        String(name.map { illegal.contains($0) ? Character(replacer.first.map(String.init) ?? "_") : $0 })
            .precomposedStringWithCanonicalMapping
    }

    /// Path components have a hard byte limit; truncate rather than fail at write time.
    public static func fixLongName(_ name: String) -> String {
        name.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0.prefix(segmentLimit)) }
            .joined(separator: "/")
    }

    /// A component that is only dots or spaces is invisible to Finder and breaks path joins.
    public static func antiDot(_ name: String) -> String {
        var trimmed = name
        while let last = trimmed.last, last == "." || last == " " || last.isNewline {
            trimmed.removeLast()
        }
        let stripped = trimmed.replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "dot" : trimmed
    }

    public static func component(_ name: String, replacer: String) -> String {
        antiDot(fixLongName(fixName(name, replacer: replacer)))
    }

    public static func pad(_ value: Int, total: Int, settings: DownloadSettings) -> String {
        guard settings.padTracks else { return String(value) }
        var width = settings.paddingSize > 0 ? settings.paddingSize : String(max(total, 1)).count
        if settings.padSingleDigit, width == 1 { width = 2 }
        return String(format: "%0\(width)d", value)
    }
}
