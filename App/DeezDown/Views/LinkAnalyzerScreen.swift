import DeezDownKit
import SwiftUI

struct LinkAnalyzerScreen: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""
    @State private var result: Analysis?
    @State private var failure: String?
    @State private var working = false

    struct Analysis {
        var link: DeezerLink
        var title: String
        var subtitle: String
        var cover: Artwork
        var rows: [(String, String)]
        var route: Route?
    }

    var body: some View {
        ScreenScroll {
            SectionHeader("Link Analyzer", subtitle: "See what a Deezer link points at before you queue it")

            HStack(spacing: 8) {
                TextField("https://www.deezer.com/album/302127", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { Task { await analyze() } }
                Button("Analyze") { Task { await analyze() } }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
            .frame(maxWidth: 640)

            if working { ProgressView().controlSize(.small) }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.failure)
            }

            if let result {
                HStack(alignment: .top, spacing: 18) {
                    ArtworkView(picture: result.cover, side: 120, corner: Metrics.cardCorner)
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).font(.title2.weight(.semibold))
                            Text(result.subtitle).foregroundStyle(.secondary)
                        }
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                            ForEach(result.rows, id: \.0) { row in
                                GridRow {
                                    Text(row.0).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                    Text(row.1).textSelection(.enabled)
                                }
                                .font(.callout)
                            }
                        }
                        HStack(spacing: 10) {
                            DownloadButton(link: result.link)
                            if let route = result.route {
                                NavigationLink("Open", value: route)
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                            }
                        }
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .background(Color.raised, in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                }
                .transition(.opacity)
            }
        }
        .navigationTitle("Link Analyzer")
        .animation(Motion.standard, value: result?.link)
    }

    private func analyze() async {
        working = true
        failure = nil
        defer { working = false }
        do {
            let link = try await LinkParser.resolve(input.trimmingCharacters(in: .whitespaces))
            result = try await describe(link)
        } catch {
            result = nil
            failure = model.message(for: error)
        }
    }

    private func describe(_ link: DeezerLink) async throws -> Analysis {
        switch link {
        case .album(let id):
            let detail = try await model.library.album(id: id)
            return Analysis(
                link: link, title: detail.summary.title, subtitle: detail.summary.artist,
                cover: detail.summary.cover,
                rows: [
                    ("Type", detail.summary.recordType.displayName), ("Album ID", detail.summary.id),
                    ("Tracks", String(detail.tracks.count)), ("Discs", String(detail.discTotal)),
                    ("Released", detail.releaseDate), ("Label", detail.label),
                    ("Genres", detail.genres.joined(separator: ", ")),
                    ("Duration", detail.duration.formattedDuration),
                    ("Explicit", detail.summary.explicit ? "Yes" : "No"),
                ].filter { !$0.1.isEmpty },
                route: .album(id)
            )
        case .playlist(let id):
            let detail = try await model.library.playlist(id: id)
            return Analysis(
                link: link, title: detail.summary.title, subtitle: "By \(detail.summary.owner)",
                cover: detail.summary.picture,
                rows: [
                    ("Type", "Playlist"), ("Playlist ID", detail.summary.id),
                    ("Tracks", String(detail.tracks.count)),
                    ("Duration", detail.duration.formattedDuration),
                ],
                route: .playlist(id)
            )
        case .artist(let id, let tab):
            return try await describeArtist(id: id, subtitle: tab.title, link: link)
        case .artistTop(let id):
            return try await describeArtist(id: id, subtitle: "Top Tracks", link: link)
        case .track(let rawID):
            return try await describeTrack(rawID: rawID, link: link)
        }
    }

    private func describeArtist(id: String, subtitle: String, link: DeezerLink) async throws -> Analysis {
            let detail = try await model.library.artist(id: id)
            return Analysis(
                link: link, title: detail.summary.name, subtitle: subtitle,
                cover: detail.summary.picture,
                rows: [
                    ("Type", "Artist"), ("Artist ID", detail.summary.id),
                    ("Fans", detail.summary.fans.formatted()),
                    ("Releases", String(detail.albums[.all]?.count ?? 0)),
                    ("Top tracks", String(detail.topTracks.count)),
                ],
                route: .artist(id)
            )
    }

    private func describeTrack(rawID: String, link: DeezerLink) async throws -> Analysis {
        let detail = try await model.library.track(id: rawID)
        let track = detail.summary

        var rows: [(String, String)] = [("Type", "Track"), ("Track ID", track.id)]
        rows.append(("ISRC", detail.isrc))
        rows.append(("Album", track.album))
        rows.append(("Disc", String(track.discNumber)))
        rows.append(("Track", track.position.map(String.init) ?? ""))
        rows.append(("Duration", track.duration.formattedDuration))
        rows.append(("Released", detail.releaseDate))
        rows.append(("BPM", detail.bpm > 0 ? String(Int(detail.bpm)) : ""))
        rows.append(("Explicit", track.explicit ? "Yes" : "No"))
        rows.append(("Available", detail.availableFormats.map(\.displayName).joined(separator: ", ")))

        return Analysis(
            link: .track(track.id), title: track.displayTitle, subtitle: track.artist,
            cover: track.cover, rows: rows.filter { !$0.1.isEmpty },
            route: .album(track.albumID)
        )
    }

}
