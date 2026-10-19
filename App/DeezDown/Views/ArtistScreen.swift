import DeezDownKit
import SwiftUI

struct ArtistScreen: View {
    @Environment(AppModel.self) private var model
    var id: String

    @State private var tab: ArtistTab = .all

    var body: some View {
        Fetched("artist-\(id)") { try await $0.artist(id: id) } content: { detail in
            ScreenScroll {
                header(detail)

                if !detail.topTracks.isEmpty {
                    SectionHeader("Top tracks") {
                        PillButton(title: "Download") {
                            Task { await model.enqueue(.artistTop(id)) }
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(detail.topTracks.prefix(10).enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, index: index + 1, showsAlbum: true)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 12)
                                .hoverHighlight(corner: 6)
                        }
                    }
                    .padding(.vertical, 6)
                    .background(Color.raised, in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06))
                    }
                }

                UnderlineTabs(selection: $tab, options: availableTabs(detail))
                    .padding(.top, 4)

                if let albums = detail.albums[tab] ?? detail.albums[.all], !albums.isEmpty {
                    CardGrid(items: albums) { album in
                        MediaCard(album, subtitle: subtitle(for: album))
                    }
                }

                if !detail.biography.isEmpty {
                    SectionHeader("About")
                    Text(detail.biography)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 720, alignment: .leading)
                }
            }
        }
        .environment(\.currentRoute, .artist(id))
    }

    private func subtitle(for album: AlbumSummary) -> String {
        [album.year, album.recordType.displayName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func availableTabs(_ detail: ArtistDetail) -> [(value: ArtistTab, title: String)] {
        ArtistTab.allCases
            .filter { detail.albums[$0]?.isEmpty == false }
            .map { ($0, $0.title) }
    }

    private func header(_ detail: ArtistDetail) -> some View {
        DetailHeader(
            picture: detail.summary.picture, kind: "Artist", title: detail.summary.name,
            link: .artist(id, tab: tab), download: "Download \(tab.title)"
        ) {
            Text("\(detail.summary.fans.formatted()) fans • \(detail.albums[.all]?.count ?? 0) releases")
        }
    }
}
