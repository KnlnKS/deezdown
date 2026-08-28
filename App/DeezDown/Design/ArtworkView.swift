import DeezDownKit
import SwiftUI

actor ArtworkLoader {
    static let shared = ArtworkLoader()

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init() {
        cache.countLimit = 400
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    func image(for picture: Artwork, size: Int) async -> NSImage? {
        guard let url = picture.url(size: Artwork.clamped(size), format: .jpeg(quality: 80)) else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let running = inFlight[url] { return await running.value }

        let task = Task<NSImage?, Never> { [session] in
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return NSImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

struct ArtworkView: View {
    var picture: Artwork
    var side: CGFloat
    var corner: CGFloat = Metrics.artworkCorner

    @State private var image: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Color.sunken)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: picture.kind == .artist ? "music.mic" : "music.note")
                        .font(.system(size: side * 0.3, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .frame(width: side, height: side)
            .animation(Motion.quick, value: image != nil)
            .task(id: picture) {
                image = await ArtworkLoader.shared.image(
                    for: picture, size: Int(side * displayScale)
                )
            }
    }
}

struct CircularArtworkView: View {
    var picture: Artwork
    var side: CGFloat

    var body: some View {
        ArtworkView(picture: picture, side: side, corner: side / 2)
    }
}
