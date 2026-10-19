import Foundation

public struct Lyrics: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        public var timestamp: String
        public var milliseconds: Int
        public var text: String
    }

    public var unsynced: String?
    public var lines: [Line]

    /// Every entry, in order; blank lines borrow the timestamp of the next timed line.
    public var lrc: String {
        guard !lines.isEmpty else { return "" }
        var stamps = [String](repeating: "", count: lines.count)
        var carried = ""
        for index in lines.indices.reversed() {
            if !lines[index].timestamp.isEmpty { carried = lines[index].timestamp }
            stamps[index] = carried
        }
        return zip(stamps, lines).map { "\($0)\($1.text)\r\n" }.joined()
    }

    /// SYLT wants timed content only.
    public var id3Sync: [(text: String, milliseconds: Int)] {
        lines.filter { !$0.text.isEmpty }.map { ($0.text, $0.milliseconds) }
    }

    init(results: JSONValue) {
        unsynced = results["LYRICS_TEXT"].stringValue
        lines = results["LYRICS_SYNC_JSON"].arrayValue.map { entry in
            Line(
                timestamp: entry["lrc_timestamp"].stringValue ?? "",
                milliseconds: entry["milliseconds"].intValue ?? 0,
                text: (entry["line"].stringValue ?? "").decodingHTMLEntities
            )
        }
    }
}

extension String {
    var decodingHTMLEntities: String {
        guard contains("&") else { return self }
        var output = self
        for (entity, replacement) in [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&apos;", "'"), ("&#39;", "'"), ("&nbsp;", " "),
        ] {
            output = output.replacingOccurrences(of: entity, with: replacement)
        }
        return output
    }
}
