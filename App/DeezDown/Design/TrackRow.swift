import DeezDownKit
import SwiftUI

struct TrackRow: View {
    @Environment(AppModel.self) private var model

    var track: TrackSummary
    var index: Int?
    var showsArtwork = false
    var showsAlbum = false

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(track.displayTitle)
                        .lineLimit(1)
                    if track.explicit { ExplicitBadge() }
                }
                if showsArtwork {
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !showsArtwork {
                Text(track.artist)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 170, alignment: .leading)
            }
            if showsAlbum {
                Text(track.album)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 170, alignment: .leading)
            }

            Text(track.duration.formattedDuration)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            DownloadIconButton(link: track.link)
                .opacity(hovering ? 1 : 0.35)
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .downloadContextMenu(track.link)
    }

    @ViewBuilder
    private var leading: some View {
        if showsArtwork {
            ZStack {
                ArtworkView(picture: track.cover, side: 36, corner: 6)
                previewOverlay(size: 36)
            }
            .frame(width: 36, height: 36)
        } else {
            ZStack {
                if hovering || isPlaying {
                    previewOverlay(size: 24)
                } else {
                    Text(index.map(String.init) ?? "—")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28)
        }
    }

    private var isPlaying: Bool { model.player.isPlaying(track.id) }

    @ViewBuilder
    private func previewOverlay(size: CGFloat) -> some View {
        if track.previewURL != nil {
            Button {
                model.player.toggle(track)
            } label: {
                ZStack {
                    if showsArtwork {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.black.opacity(hovering || isPlaying ? 0.45 : 0))
                    }
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: size * 0.36))
                        .foregroundStyle(showsArtwork ? .white : Color.brand)
                        .opacity(showsArtwork ? (hovering || isPlaying ? 1 : 0) : 1)
                }
            }
            .buttonStyle(.plain)
            .pressable(scale: 0.9)
            .frame(width: size, height: size)
            .help(isPlaying ? "Stop preview" : "Play a 30 second preview")
        }
    }
}

struct DiscHeader: View {
    var number: Int

    var body: some View {
        Label("Disc \(number)", systemImage: "opticaldisc")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }
}

struct SelectionFooter: View {
    @Environment(AppModel.self) private var model
    var tracks: [TrackSummary]
    var selection: Set<TrackSummary.ID>

    var body: some View {
        if !selection.isEmpty {
            HStack {
                Text("\(selection.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download Selection") {
                    let chosen = tracks.filter { selection.contains($0.id) }
                    Task { await model.enqueue(tracks: chosen) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
