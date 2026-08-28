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

    /// Deezer will render any square size, but each one is a separate download and a separate
    /// cache entry. Snapping to a few steps lets a grid card and a detail header share one image.
    private static let steps = [56, 120, 264, 500, 1000]

    static func step(for size: Int) -> Int {
        Artwork.clamped(steps.first { $0 >= size } ?? Artwork.maximumSize)
    }

    func image(for picture: Artwork, size: Int) async -> NSImage? {
        guard let url = picture.url(size: Self.step(for: size), format: .jpeg(quality: 80)) else { return nil }
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

/// Sizes itself from its container rather than a fixed side, so grid cards stay square
/// without measuring geometry (which feeds back into the layout that produced it).
struct FillingArtworkView: View {
    var picture: Artwork
    var isCircular = false

    @State private var image: NSImage?

    private var shape: AnyShape {
        isCircular
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
    }

    var body: some View {
        shape
            .fill(Color.sunken)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: picture.kind == .artist ? "music.mic" : "music.note")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(shape)
            .overlay { shape.stroke(Color.primary.opacity(0.06), lineWidth: 1) }
            .animation(Motion.quick, value: image != nil)
            .task(id: picture) {
                image = await ArtworkLoader.shared.image(for: picture, size: 500)
            }
    }
}
