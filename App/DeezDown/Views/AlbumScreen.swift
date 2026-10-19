import DeezDownKit
import SwiftUI

struct AlbumScreen: View {
    var id: String

    var body: some View {
        Fetched("album-\(id)") { try await $0.album(id: id) } content: { detail in
            TrackList(tracks: detail.tracks) {
                ForEach(rows(detail)) { row in
                    switch row.kind {
                    case .disc(let number):
                        Label("Disc \(number)", systemImage: "opticaldisc")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .selectionDisabled()
                    case .track(let track, let index):
                        TrackRow(track: track, index: index, showsArtist: false).tag(track.id)
                    }
                }
            } header: {
                header(detail)
            }
        }
        .environment(\.currentRoute, .album(id))
    }

    private struct Row: Identifiable {
        enum Kind {
            case disc(Int)
            case track(TrackSummary, Int)
        }
        var id: String
        var kind: Kind
    }

    private func rows(_ detail: AlbumDetail) -> [Row] {
        var rows: [Row] = []
        var lastDisc = 0
        for track in detail.tracks {
            if detail.discTotal > 1, track.discNumber != lastDisc {
                lastDisc = track.discNumber
                rows.append(Row(id: "disc-\(lastDisc)", kind: .disc(lastDisc)))
            }
            rows.append(Row(id: track.id, kind: .track(track, track.position ?? 0)))
        }
        return rows
    }

    private func header(_ detail: AlbumDetail) -> some View {
        DetailHeader(
            picture: detail.summary.cover, kind: detail.summary.recordType.displayName,
            title: detail.summary.title, explicit: detail.summary.explicit,
            link: detail.summary.link, download: "Download Album"
        ) {
            NavigationLink(value: Route.artist(detail.summary.artistID)) {
                HStack(spacing: 7) {
                    ArtworkView(picture: Artwork(md5: detail.artistPicture, kind: .artist), side: 22)
                    Text(detail.summary.artist).font(.title3.weight(.medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .hoverHighlight(corner: 6)

            Text(metadata(detail))
        }
    }

    private func metadata(_ detail: AlbumDetail) -> String {
        var parts: [String] = []
        if !detail.summary.year.isEmpty { parts.append(detail.summary.year) }
        parts.append("\(detail.tracks.count) track\(detail.tracks.count == 1 ? "" : "s")")
        parts.append(detail.duration.formattedDuration)
        if let genre = detail.genres.first { parts.append(genre) }
        if !detail.label.isEmpty { parts.append(detail.label) }
        return parts.joined(separator: " • ")
    }
}
