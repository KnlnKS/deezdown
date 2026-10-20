import AppKit
import Foundation

/// Finder reads embedded art from MP3 but not from FLAC or MP4, so those files get the
/// cover attached as a custom icon instead. Verified against a correctly tagged reference
/// file: without this, Finder shows a generic note for FLAC no matter who wrote the tags.
enum FinderIcon {
    static func isNeeded(for format: TrackFormat) -> Bool {
        format.fileExtension != "mp3"
    }

    /// About 60 ms a file, which on the main actor stalled the app as each track finished.
    @concurrent
    static func apply(_ artwork: Data, to url: URL) async {
        guard let image = NSImage(data: artwork) else { return }
        NSWorkspace.shared.setIcon(image, forFile: url.path(percentEncoded: false), options: [])
    }
}
