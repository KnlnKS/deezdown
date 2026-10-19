import Foundation

public enum NameSanitizer {
    static let illegal: Set<Character> = ["\0", "/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
    /// APFS takes 255 UTF-8 bytes a name, and a track's name grows on disk by up to a Keep Both
    /// counter, its extension and the suffix it is written under.
    public static let segmentLimit = 255 - " (999).flac.retag".utf8.count

    /// Deezer titles routinely contain characters HFS+/APFS or Finder will not accept.
    public static func fixName(_ name: String, replacer: String) -> String {
        var output = ""
        for character in name {
            if illegal.contains(character) { output += replacer } else { output.append(character) }
        }
        return output.precomposedStringWithCanonicalMapping
    }

    /// Path components have a hard byte limit; cut whole characters rather than fail at write time.
    public static func fixLongName(_ name: String) -> String {
        guard name.utf8.count > segmentLimit else { return name }
        var bytes = 0
        return String(name.prefix { character in
            bytes += character.utf8.count
            return bytes <= segmentLimit
        })
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
