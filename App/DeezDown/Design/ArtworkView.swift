import DeezDownKit
import SwiftUI

actor ArtworkLoader {
    static let shared = ArtworkLoader()

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init() {
        cache.countLimit = 400
        // A grid of 500px covers is a megabyte each decoded; a count alone is not a budget.
        cache.totalCostLimit = 256 << 20
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    /// Deezer will render any square size, but each one is a separate download and a separate
    /// cache entry. Snapping to a few steps lets a grid card and a detail header share one image.
    private static let steps = [56, 120, 264, 500, 1000]

    static func step(for size: Int) -> Int {
        steps.first { $0 >= size } ?? 1200
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
        if let image {
            let pixels = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
            cache.setObject(image, forKey: url as NSURL, cost: pixels * 4)
        }
        return image
    }
}

/// The art itself, wherever it appears: one load, one placeholder, one well, one hairline.
/// Callers differ only in whether they fix the size or let the layout decide.
private struct ArtworkContent<Outline: InsettableShape>: View {
    var picture: Artwork
    var shape: Outline
    var requestedSize: Int
    var placeholderSize: CGFloat
    var fillsContainer = false

    @State private var image: NSImage?

    var body: some View {
        well
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: picture.kind == .artist ? "music.mic" : "music.note")
                        .font(.system(size: placeholderSize, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1) }
            .animation(Motion.quick, value: image != nil)
            .task(id: picture) {
                image = await ArtworkLoader.shared.image(for: picture, size: requestedSize)
            }
    }

    @ViewBuilder
    private var well: some View {
        if fillsContainer {
            shape.fill(Color.sunken).aspectRatio(1, contentMode: .fit)
        } else {
            shape.fill(Color.sunken)
        }
    }
}

extension Artwork {
    /// People are round, records square.
    var isRound: Bool { kind == .artist || kind == .user }
}

struct ArtworkView: View {
    var picture: Artwork
    var side: CGFloat
    var corner: CGFloat = Metrics.artworkCorner

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ArtworkContent(
            picture: picture,
            shape: RoundedRectangle(cornerRadius: picture.isRound ? side / 2 : corner, style: .continuous),
            requestedSize: Int(side * displayScale),
            placeholderSize: side * 0.3
        )
        .frame(width: side, height: side)
    }
}

/// Sizes itself from its container rather than a fixed side, so grid cards stay square
/// without measuring geometry (which feeds back into the layout that produced it).
struct FillingArtworkView: View {
    var picture: Artwork

    var body: some View {
        if picture.isRound {
            ArtworkContent(
                picture: picture, shape: Circle(), requestedSize: 500,
                placeholderSize: 34, fillsContainer: true
            )
        } else {
            ArtworkContent(
                picture: picture,
                shape: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous),
                requestedSize: 500, placeholderSize: 34, fillsContainer: true
            )
        }
    }
}
