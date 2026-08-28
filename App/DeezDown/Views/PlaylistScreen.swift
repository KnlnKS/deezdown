import DeezDownKit
import SwiftUI

struct PlaylistScreen: View {
    @Environment(AppModel.self) private var model
    var id: String

    @State private var state: LoadState<PlaylistDetail> = .loading
    @State private var selection: Set<TrackSummary.ID> = []

    var body: some View {
        AsyncContent(state: state, retry: { Task { await load() } }) { detail in
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Section {
                        ForEach(Array(detail.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, index: index + 1, showsArtwork: true, showsAlbum: true)
                                .tag(track.id)
                                .trackRowInsets()
                        }
                    } header: {
                        PlaylistHeader(detail: detail)
                    }
                }
                .listStyle(.inset)
                SelectionFooter(tracks: detail.tracks, selection: selection)
            }
            .animation(Motion.standard, value: selection.isEmpty)
        }
        .navigationTitle(title)
        .environment(\.currentRoute, .playlist(id))
        .task(id: id) { await load() }
    }

    private var title: String {
        if case .loaded(let detail) = state { return detail.summary.title }
        return "Playlist"
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await model.library.playlist(id: id))
        } catch {
            state = .failed(model.message(for: error))
        }
    }
}

private struct PlaylistHeader: View {
    var detail: PlaylistDetail

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            ArtworkView(picture: detail.summary.picture, side: 190, corner: Metrics.cardCorner)
                .shadow(color: .black.opacity(0.28), radius: 22, y: 10)

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Playlist")

                DisplayTitle(text: detail.summary.title)

                if !detail.summary.description.isEmpty {
                    Text(detail.summary.description.strippingHTML)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 520, alignment: .leading)
                }

                Text(metadata)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                DownloadButton(link: detail.summary.link, title: "Download Playlist")
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
        if !detail.summary.owner.isEmpty { parts.append("By \(detail.summary.owner)") }
        parts.append("\(detail.tracks.count) track\(detail.tracks.count == 1 ? "" : "s")")
        parts.append(detail.duration.formattedDuration)
        return parts.joined(separator: " • ")
    }
}
