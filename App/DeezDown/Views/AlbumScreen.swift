import DeezDownKit
import SwiftUI

struct AlbumScreen: View {
    @Environment(AppModel.self) private var model
    var id: String

    @State private var state: LoadState<AlbumDetail> = .loading
    @State private var selection: Set<TrackSummary.ID> = []

    var body: some View {
        AsyncContent(state: state, retry: { Task { await load() } }) { detail in
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Section {
                        ForEach(rows(detail), id: \.id) { row in
                            switch row.kind {
                            case .disc(let number):
                                DiscHeader(number: number).selectionDisabled().trackRowInsets()
                            case .track(let track, let index):
                                TrackRow(track: track, index: index, showsArtist: false)
                                    .tag(track.id)
                                    .trackRowInsets()
                            }
                        }
                    } header: {
                        AlbumHeader(detail: detail)
                    }
                }
                .listStyle(.inset)
                SelectionFooter(tracks: detail.tracks, selection: selection)
            }
            .animation(Motion.standard, value: selection.isEmpty)
        }
        .navigationTitle(title)
        .environment(\.currentRoute, .album(id))
        .task(id: id) { await load() }
    }

    private var title: String {
        if case .loaded(let detail) = state { return detail.summary.title }
        return "Album"
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

    private func load() async {
        await model.load("album-\(id)", into: { state = $0 }) { try await model.library.album(id: id) }
    }
}

private struct AlbumHeader: View {
    var detail: AlbumDetail

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            ArtworkView(picture: detail.summary.cover, side: 190, corner: Metrics.cardCorner)
                .shadow(color: .black.opacity(0.28), radius: 22, y: 10)

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: detail.summary.recordType.displayName)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    DisplayTitle(text: detail.summary.title)
                    if detail.summary.explicit { ExplicitBadge() }
                }

                NavigationLink(value: Route.artist(detail.summary.artistID)) {
                    HStack(spacing: 7) {
                        CircularArtworkView(
                            picture: Artwork(md5: detail.artistPicture, kind: .artist), side: 22
                        )
                        Text(detail.summary.artist).font(.title3.weight(.medium))
                    }
                }
                .buttonStyle(.plain)
                .hoverHighlight(corner: 6)

                Text(metadata)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                DownloadButton(link: detail.summary.link, title: "Download Album")
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.listGutter)
        .padding(.vertical, 18)
        .textCase(nil)
        .foregroundStyle(.primary)
    }

    private var metadata: String {
        var parts: [String] = []
        if !detail.summary.year.isEmpty { parts.append(detail.summary.year) }
        parts.append("\(detail.tracks.count) track\(detail.tracks.count == 1 ? "" : "s")")
        parts.append(detail.duration.formattedDuration)
        if let genre = detail.genres.first { parts.append(genre) }
        if !detail.label.isEmpty { parts.append(detail.label) }
        return parts.joined(separator: " • ")
    }
}
