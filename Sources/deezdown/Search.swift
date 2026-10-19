import ArgumentParser
import DeezDownKit
import Foundation

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Search Deezer tracks, albums, artists, or playlists.")

    @OptionGroup var options: GlobalOptions
    @Argument(help: "Search words.") var query: [String]
    @Option(name: .long, help: "Result type: track, album, artist, playlist, or all (default: all).") var type: String?
    @Option(name: .long, help: "Page number, starting at 1.") var page = 1
    @Option(name: .long, help: "Results per type and page (1...100).") var limit = 40
    @Option(name: .long, help: "Sign in with this ARL and remember it.") var arl: String?

    func validate() throws {
        guard !query.isEmpty, !query.joined().trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError("Enter search words.")
        }
        guard page > 0, (1...100).contains(limit), page <= Int.max / limit else {
            throw ValidationError("Page must be positive and limit must be between 1 and 100.")
        }
        if let type, type.lowercased() != "all", SearchKind(rawValue: type.lowercased()) == nil {
            throw ValidationError("Type must be track, album, artist, playlist, or all.")
        }
    }

    func run() async throws {
        let (session, _) = try await options.signIn(arl: arl)
        let library = DeezerLibrary(session: session)
        let words = query.joined(separator: " ")
        let start = (page - 1) * limit

        if let type, let kind = SearchKind(rawValue: type.lowercased()) {
            let result = try await fetch(library, words: words, kind: kind, start: start)
            printPage(result, start: start)
        } else {
            var results: [SearchKind: ResultPage] = [:]
            try await withThrowingTaskGroup(of: ResultPage.self) { group in
                for kind in SearchKind.allCases {
                    group.addTask { try await fetch(library, words: words, kind: kind, start: start) }
                }
                for try await result in group { results[result.kind] = result }
            }
            for kind in SearchKind.allCases {
                if let result = results[kind] { printPage(result, start: start) }
            }
        }
    }

    private struct ResultPage: Sendable {
        let kind: SearchKind
        let rows: [(String, DeezerLink)]
        let total: Int
    }

    private func fetch(_ library: DeezerLibrary, words: String, kind: SearchKind, start: Int) async throws -> ResultPage {
        func page<Item: Searchable>(_ type: Item.Type, _ line: (Item) -> String) async throws -> ResultPage {
            let (items, total) = try await library.search(words, as: type, start: start, limit: limit)
            return ResultPage(kind: kind, rows: items.map { (line($0), $0.link) }, total: total)
        }
        return switch kind {
        case .track: try await page(TrackSummary.self) { "\($0.artist) — \($0.title) [\($0.album)]" }
        case .album: try await page(AlbumSummary.self) { "\($0.artist) — \($0.title)" }
        case .artist: try await page(ArtistSummary.self) { $0.name }
        case .playlist: try await page(PlaylistSummary.self) { "\($0.title) — \($0.owner)" }
        }
    }

    private func printPage(_ result: ResultPage, start: Int) {
        print("\(result.kind.title) · page \(page) · \(result.total) reported")
        for (index, row) in result.rows.enumerated() {
            print("\(start + index + 1). \(row.0)\n   \(row.1.webURL?.absoluteString ?? "")")
        }
        if result.rows.isEmpty { print("No results on this page.") }
    }
}
