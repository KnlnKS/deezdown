import AVFoundation
import DeezDownKit
import Observation
import SwiftUI

/// Deezer's 30-second preview clips are unencrypted MP3s, so AVPlayer can take them directly.
@Observable
final class PreviewPlayer {
    private(set) var playingTrackID: String?

    private let player = AVPlayer()
    private var endObserver: (any NSObjectProtocol)?

    init() {
        player.volume = 0.8
    }

    func isPlaying(_ trackID: String) -> Bool { playingTrackID == trackID }

    func toggle(_ track: TrackSummary) {
        if playingTrackID == track.id {
            stop()
        } else if let url = track.previewURL {
            play(url, trackID: track.id)
        }
    }

    private func play(_ url: URL, trackID: String) {
        forgetEndObserver()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        playingTrackID = trackID
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        forgetEndObserver()
        player.pause()
        player.replaceCurrentItem(with: nil)
        playingTrackID = nil
    }

    private func forgetEndObserver() {
        guard let endObserver else { return }
        NotificationCenter.default.removeObserver(endObserver)
        self.endObserver = nil
    }
}
