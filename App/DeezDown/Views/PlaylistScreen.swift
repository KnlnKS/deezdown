import DeezDownKit
import SwiftUI

struct PlaylistScreen: View {
    var id: String

    var body: some View {
        Fetched("playlist-\(id)") { try await $0.playlist(id: id) } content: { detail in
            TrackList(tracks: detail.tracks) {
                ForEach(detail.tracks) { track in
                    TrackRow(track: track, showsArtwork: true, showsAlbum: true).tag(track.id)
                }
            } header: {
                header(detail)
            }
        }
        .environment(\.currentRoute, .playlist(id))
    }

    private func header(_ detail: PlaylistDetail) -> some View {
        DetailHeader(
            picture: detail.summary.picture, kind: "Playlist", title: detail.summary.title,
            link: detail.summary.link, download: "Download Playlist"
        ) {
            if !detail.summary.description.isEmpty {
                Text(detail.summary.description.strippingHTML)
                    .lineLimit(2)
                    .frame(maxWidth: 520, alignment: .leading)
            }
            Text(metadata(detail))
        }
    }

    private func metadata(_ detail: PlaylistDetail) -> String {
        let owner = detail.summary.owner.isEmpty ? [] : ["By \(detail.summary.owner)"]
        return (owner + [detail.tracks.count.tracksLabel, detail.duration.formattedDuration]).joined(separator: " • ")
    }
}
