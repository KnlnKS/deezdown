import Foundation

public enum TemplateEngine {
    /// deemix drops one leading space with these when they render empty, so titles don't
    /// end up with a double space where the feature or advisory marker would have been.
    static let spaceEating: Set<String> = ["featartists", "explicit"]

    public static func render(_ template: String, _ variables: [String: String]) -> String {
        var output = template
        for (name, value) in variables {
            let token = "%\(name)%"
            if value.isEmpty, spaceEating.contains(name) {
                output = output.replacingOccurrences(of: " \(token)", with: "")
            }
            output = output.replacingOccurrences(of: token, with: value)
        }
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
