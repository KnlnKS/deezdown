import Foundation

public enum TemplateEngine {
    /// deemix drops one leading space with these when they render empty, so titles don't
    /// end up with a double space where the feature or advisory marker would have been.
    static let spaceEating: Set<String> = ["featartists", "explicit"]

    /// One pass over the template. Sweeping the whole string once per variable was both
    /// slower and order-dependent: a value that happened to contain a token was substituted
    /// again or not depending on how the dictionary happened to be laid out.
    public static func render(_ template: String, _ variables: [String: String]) -> String {
        var output = ""
        output.reserveCapacity(template.count)
        var rest = Substring(template)

        while let start = rest.firstIndex(of: "%") {
            let nameStart = rest.index(after: start)
            guard let end = rest[nameStart...].firstIndex(of: "%") else { break }
            guard let value = variables[String(rest[nameStart..<end])] else {
                // Not a variable, so the closing marker may yet open a real one.
                output += rest[...start]
                rest = rest[nameStart...]
                continue
            }
            output += rest[..<start]
            if value.isEmpty, spaceEating.contains(String(rest[nameStart..<end])), output.last == " " {
                output.removeLast()
            }
            output += value
            rest = rest[rest.index(after: end)...]
        }

        output += rest
        return output.trimmingCharacters(in: .whitespaces)
    }

    public static let trackVariables = [
        "title", "artist", "artists", "tagsartists", "allartists", "mainartists", "featartists",
        "album", "albumartist", "tracknumber", "tracktotal", "discnumber", "disctotal", "genre",
        "year", "date", "bpm", "label", "isrc", "upc", "explicit", "track_id", "album_id",
        "artist_id", "playlist_id", "position",
    ]

    public static let albumVariables = [
        "album", "album_id", "genre", "artist", "artists", "artist_id", "root_artist",
        "root_artist_id", "playlist", "tracktotal", "disctotal", "type", "upc", "explicit",
        "label", "year", "date", "bitrate",
    ]

    public static let artistVariables = ["artist", "artist_id", "root_artist", "root_artist_id"]

    public static let playlistVariables = [
        "playlist", "playlist_id", "owner", "owner_id", "year", "date", "explicit", "today",
    ]

    public static let collectionVariables = [
        "title", "artist", "size", "type", "id", "playlist", "bitrate",
    ]
}
