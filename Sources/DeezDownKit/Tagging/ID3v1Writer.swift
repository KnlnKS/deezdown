import Foundation

enum ID3v1Writer {
    static let genres = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal",
        "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial",
        "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop",
        "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House", "Game",
        "Sound Clip", "Gospel", "Noise", "AlternRock", "Bass", "Soul", "Punk", "Space", "Meditative",
        "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic", "Darkwave", "Techno-Industrial",
        "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave",
        "Psychadelic", "Rave", "Showtunes", "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka",
        "Retro", "Musical", "Rock & Roll", "Hard Rock", "Folk", "Folk-Rock", "National Folk", "Swing",
        "Fast Fusion", "Bebob", "Latin", "Revival", "Celtic", "Bluegrass", "Avantgarde", "Gothic Rock",
        "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock", "Big Band", "Chorus",
        "Easy Listening", "Acoustic", "Humour", "Speech", "Chanson", "Opera", "Chamber Music", "Sonata",
        "Symphony", "Booty Bass", "Primus", "Porn Groove", "Satire", "Slow Jam", "Club", "Tango", "Samba",
        "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle", "Duet", "Punk Rock", "Drum Solo",
        "A capella", "Euro-House", "Dance Hall", "Goa", "Drum & Bass", "Club-House", "Hardcore", "Terror",
        "Indie", "BritPop", "Negerpunk", "Polsk Punk", "Beat", "Christian Gangsta Rap", "Heavy Metal",
        "Black Metal", "Crossover", "Contemporary Christian", "Christian Rock", "Merengue", "Salsa",
        "Trash Metal", "Anime", "Jpop", "Synthpop", "Abstract", "Art Rock", "Baroque", "Bhangra", "Big Beat",
        "Breakbeat", "Chillout", "Downtempo", "Dub", "EBM", "Eclectic", "Electro", "Electroclash", "Emo",
        "Experimental", "Garage", "Global", "IDM", "Illbient", "Industro-Goth", "Jam Band", "Krautrock",
        "Leftfield", "Lounge", "Math Rock", "New Romantic", "Nu-Breakz", "Post-Punk", "Post-Rock", "Psytrance",
        "Shoegaze", "Space Rock", "Trop Rock", "World Music", "Neoclassical", "Audiobook", "Audio Theatre",
        "Neue Deutsche Welle", "Podcast", "Indie Rock", "G-Funk", "Dubstep", "Garage Rock", "Psybient",
    ]

    /// ID3v1 predates Unicode; anything above Latin-1 becomes a question mark.
    private static func latin(_ text: String, _ length: Int) -> [UInt8] {
        var bytes = text.unicodeScalars.map { $0.value < 256 ? UInt8($0.value) : UInt8(ascii: "?") }
        bytes = Array(bytes.prefix(length))
        return bytes + [UInt8](repeating: 0, count: length - bytes.count)
    }

    static func tag(title: String, artist: String, album: String, year: String, trackNumber: Int, genre: String?)
        -> Data
    {
        var bytes = Array("TAG".utf8)
        bytes += latin(title, 30)
        bytes += latin(artist, 30)
        bytes += latin(album, 30)
        bytes += latin(year, 4)
        bytes += [UInt8](repeating: 0, count: 30)
        if trackNumber > 0, trackNumber < 256 {
            bytes[125] = 0
            bytes[126] = UInt8(trackNumber)
        }
        let index = genre.flatMap { name in genres.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame } }
        bytes.append(index.map(UInt8.init) ?? 255)
        return Data(bytes)
    }
}
