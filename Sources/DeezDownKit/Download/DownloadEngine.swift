import Foundation
import Synchronization

public actor DownloadEngine {
    private struct TrackJob: Sendable {
        var itemID: String
        var index: Int
        var media: ResolvedMedia?
        var failure: DownloadFailure?
    }

    private struct ItemState {
        var collection: ResolvedCollection
        var context: DownloadContext
        var tracks: [Track]
        var files: [URL?]
        var inFlight: [Int: Double] = [:]
        var remaining: Int
        var artwork: Data?
        var searched: [String] = []
        var failures: [String] = []
    }

    private let session: DeezerSession
    private let paths: AppPaths
    private let artworkStore = ArtworkStore()
    private let downloader = MediaDownloader()

    private var settings: DownloadSettings
    private var items: [String: QueueItem] = [:]
    private var order: [String] = []
    private var states: [String: ItemState] = [:]
    private var jobs: [TrackJob] = []
    private var activeWorkers = 0
    private var directorRunning = false
    private var canceled: Set<String> = []
    private var observers: [UUID: AsyncStream<[QueueItem]>.Continuation] = [:]

    public init(session: DeezerSession, settings: DownloadSettings, paths: AppPaths = AppPaths()) {
        self.session = session
        self.settings = settings
        self.paths = paths
    }

    // MARK: - Observation

    public var queue: [QueueItem] { order.compactMap { items[$0] } }

    public func events() -> AsyncStream<[QueueItem]> {
        AsyncStream { continuation in
            let id = UUID()
            observers[id] = continuation
            continuation.yield(queue)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func publish() {
        let snapshot = queue
        for continuation in observers.values { continuation.yield(snapshot) }
    }

    public func updateSettings(_ newValue: DownloadSettings) {
        settings = newValue
    }

    // MARK: - Queueing

    @discardableResult
    public func enqueue(_ link: DeezerLink, format requested: TrackFormat? = nil) async throws -> [String] {
        guard let user = await session.user else { throw DeezerError.notLoggedIn }
        var format = requested ?? settings.maxBitrate
        if !user.canStream(format) {
            guard settings.fallbackBitrate else { throw DownloadFailure(.wrongLicense) }
            format = user.highestAvailableFormat
        }

        let links = try await expand(link)
        var added: [String] = []
        for entry in links {
            let id = QueueItem.identifier(for: entry.link, format: format)
            guard items[id] == nil else { continue }
            var item = QueueItem(
                id: id, link: entry.link, title: entry.title, subtitle: entry.subtitle,
                cover: entry.cover, format: format
            )
            item.totalTracks = entry.trackCount
            items[id] = item
            order.append(id)
            added.append(id)
        }
        guard !added.isEmpty else { return [] }
        persist()
        publish()
        pump()
        return added
    }

    private struct PendingLink {
        var link: DeezerLink
        var title: String
        var subtitle: String
        var cover: Artwork
        var trackCount: Int
    }

    /// Artist links become one queue entry per album, resolved cheaply from the discography.
    private func expand(_ link: DeezerLink) async throws -> [PendingLink] {
        guard case .artist(let id, let tab) = link else {
            return [
                PendingLink(
                    link: link, title: link.placeholderTitle, subtitle: "Looking up tracks…",
                    cover: Artwork(md5: "", kind: .cover), trackCount: 0
                )
            ]
        }
        let resolver = LinkResolver(session: session, settings: settings)
        let collections = try await resolver.resolve(.artist(id, tab: tab))
        return collections.map {
            PendingLink(
                link: $0.link, title: $0.title, subtitle: $0.subtitle,
                cover: $0.cover, trackCount: $0.tracks.count
            )
        }
    }

    public func cancel(_ id: String) {
        guard var item = items[id] else { return }
        canceled.insert(id)
        jobs.removeAll { $0.itemID == id }
        if !item.status.isFinished {
            item.status = .canceled
            items[id] = item
        }
        states[id] = nil
        persist()
        publish()
        pump()
    }

    public func cancelAll() {
        for id in order where !(items[id]?.status.isFinished ?? true) { canceled.insert(id) }
        jobs.removeAll()
        for id in order {
            guard var item = items[id], !item.status.isFinished else { continue }
            item.status = .canceled
            items[id] = item
        }
        states.removeAll()
        persist()
        publish()
    }

    public func remove(_ id: String) {
        canceled.insert(id)
        jobs.removeAll { $0.itemID == id }
        items[id] = nil
        states[id] = nil
        order.removeAll { $0 == id }
        try? FileManager.default.removeItem(at: paths.queueDirectory.appending(path: "\(id).json"))
        persist()
        publish()
    }

    /// Clears what needs no attention; items that failed stay so their errors can be read.
    public func clearFinished() {
        for id in order where [.completed, .canceled].contains(items[id]?.status) { remove(id) }
    }

    public func retry(_ id: String) {
        guard var item = items[id], item.canRetry else { return }
        canceled.remove(id)
        item.status = .queued
        item.completedTracks = 0
        item.failedTracks = 0
        item.progress = 0
        item.issues = []
        items[id] = item
        states[id] = nil
        persist()
        publish()
        pump()
    }

    // MARK: - Scheduling

    private func pump() {
        startDirectorIfNeeded()
        startWorkersIfNeeded()
    }

    private func startDirectorIfNeeded() {
        guard !directorRunning else { return }
        guard order.contains(where: { items[$0]?.status == .queued }) else { return }
        guard jobs.count < settings.queueConcurrency * 4 else { return }
        directorRunning = true
        Task { await runDirector() }
    }

    private func runDirector() async {
        defer { directorRunning = false }
        while jobs.count < settings.queueConcurrency * 4 {
            guard let id = order.first(where: { items[$0]?.status == .queued }) else { return }
            await prepare(id)
            startWorkersIfNeeded()
        }
    }

    private func startWorkersIfNeeded() {
        while activeWorkers < settings.queueConcurrency, !jobs.isEmpty {
            activeWorkers += 1
            Task { await runWorker() }
        }
    }

    private func runWorker() async {
        while !jobs.isEmpty {
            let job = jobs.removeFirst()
            await perform(job)
        }
        activeWorkers -= 1
        pump()
    }

    // MARK: - Preparation

    private func prepare(_ id: String) async {
        guard var item = items[id], item.status == .queued else { return }
        item.status = .resolving
        items[id] = item
        publish()

        do {
            let resolver = LinkResolver(session: session, settings: settings)
            guard let collection = try await resolver.resolve(item.link).first else {
                throw DownloadFailure(.notOnDeezer)
            }
            guard !canceled.contains(id) else { return }

            let tracks = collection.tracks.map { $0.applying(settings) }
            let context = DownloadContext(
                playlist: collection.playlist,
                isSingleTrackDownload: collection.isSingleTrack,
                rootArtist: collection.rootArtist,
                format: item.format,
                today: CustomDate(deezerString: Self.isoToday()) ?? CustomDate()
            )

            let resolvedMedia = try await MediaResolver(session: session, settings: settings)
                .resolve(tracks, format: item.format)
            guard !canceled.contains(id) else { return }

            let artwork =
                settings.tags.cover
                ? await artworkStore.image(
                    collection.cover, size: Artwork.clamped(settings.embeddedArtworkSize),
                    format: settings.embeddedArtworkFormat)
                : nil

            states[id] = ItemState(
                collection: collection,
                context: context,
                tracks: tracks,
                files: Array(repeating: nil, count: tracks.count),
                remaining: tracks.count,
                artwork: artwork
            )

            item = items[id] ?? item
            item.title = collection.title
            item.subtitle = collection.subtitle
            item.cover = collection.cover
            item.totalTracks = tracks.count
            item.status = .downloading
            items[id] = item

            for (index, outcome) in resolvedMedia.enumerated() {
                switch outcome {
                case .success(let media):
                    let resolved = media.track.applying(settings)
                    states[id]?.tracks[index] = resolved
                    if media.track.searched {
                        states[id]?.searched.append(
                            "\(tracks[index].mainArtist.name) - \(tracks[index].title) -> \(resolved.id)"
                        )
                    }
                    jobs.append(TrackJob(itemID: id, index: index, media: media))
                case .failure(let failure):
                    jobs.append(TrackJob(itemID: id, index: index, failure: failure))
                }
            }
            if tracks.isEmpty { await finish(id) }
        } catch {
            item = items[id] ?? item
            item.status = .failed
            item.issues = [
                TrackIssue(
                    id: item.id, title: item.title, artist: item.subtitle,
                    message: (error as? DownloadFailure)?.message ?? error.localizedDescription
                )
            ]
            items[id] = item
        }
        persist()
        publish()
    }

    private static func isoToday() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Track execution

    private func perform(_ job: TrackJob) async {
        guard !canceled.contains(job.itemID), let state = states[job.itemID] else { return }
        let track = state.tracks[job.index]

        if let failure = job.failure {
            record(job.itemID, index: job.index, failure: failure, track: track)
            await finishIfDone(job.itemID)
            return
        }
        guard let media = job.media else {
            record(job.itemID, index: job.index, failure: DownloadFailure(.notAvailable), track: track)
            await finishIfDone(job.itemID)
            return
        }

        let builder = PathBuilder(settings: settings)
        let destination = builder.paths(for: track, context: state.context)
        let base = destination.directory.appending(path: destination.filename)
        let decision = OverwritePolicy.decide(
            base: base, format: media.format, duration: track.duration, mode: settings.overwriteFile
        )

        let needsLyrics =
            settings.tags.lyrics || settings.tags.syncedLyrics || settings.syncedLyrics
        async let extras = trackExtras(for: track, needsLyrics: needsLyrics)

        var enriched = track
        var file: URL

        switch decision {
        case .skip(let existing):
            _ = await extras
            complete(job.itemID, index: job.index, file: existing)
            await finishIfDone(job.itemID)
            return

        case .tagOnly(let existing):
            let (bpm, lyrics) = await extras
            enriched.bpm = bpm ?? enriched.bpm
            enriched.lyrics = lyrics ?? enriched.lyrics
            file = existing

        case .download(let target):
            file = target
            let itemID = job.itemID
            let index = job.index
            let lastReported = Mutex<Double>(0)
            do {
                try await downloader.download(media, to: target) { [weak self] written, total in
                    guard total > 0 else { return }
                    let fraction = min(1, Double(written) / Double(total))
                    let shouldReport = lastReported.withLock { last -> Bool in
                        guard fraction - last >= 0.01 || fraction >= 1 else { return false }
                        last = fraction
                        return true
                    }
                    guard shouldReport, let self else { return }
                    Task { await self.report(itemID: itemID, index: index, fraction: fraction) }
                }
            } catch let failure as DownloadFailure {
                _ = await extras
                record(job.itemID, index: job.index, failure: failure, track: track)
                await finishIfDone(job.itemID)
                return
            } catch {
                _ = await extras
                record(
                    job.itemID, index: job.index,
                    failure: DownloadFailure(.network(error.localizedDescription)), track: track
                )
                await finishIfDone(job.itemID)
                return
            }
            let (bpm, lyrics) = await extras
            enriched.bpm = bpm ?? enriched.bpm
            enriched.lyrics = lyrics ?? enriched.lyrics
        }

        do {
            try Tagger.tag(
                enriched, format: media.format, at: file,
                artwork: states[job.itemID]?.artwork, settings: settings
            )
        } catch {
            states[job.itemID]?.failures.append("\(track.id) tagging: \(error.localizedDescription)")
        }

        if settings.syncedLyrics, let lyrics = enriched.lyrics, !lyrics.lines.isEmpty {
            try? LRCWriter.write(
                lyrics,
                to: destination.directory.appending(path: "\(destination.filename).lrc"),
                overwrite: settings.overwriteFile == .overwrite || settings.overwriteFile == .tagsOnly
            )
        }

        complete(job.itemID, index: job.index, file: file)
        await finishIfDone(job.itemID)
    }

    private func trackExtras(for track: Track, needsLyrics: Bool) async -> (Double?, Lyrics?) {
        async let bpm: Double? = settings.tags.bpm && track.bpm == 0
            ? session.publicTrackBPM(id: track.id) : nil
        async let lyrics: Lyrics? = needsLyrics && track.lyrics == nil && track.lyricsID != "0"
            ? (try? await session.lyrics(trackID: track.id)).map(Lyrics.init(results:)) : nil
        return (await bpm, await lyrics)
    }

    private func report(itemID: String, index: Int, fraction: Double) {
        guard states[itemID] != nil, var item = items[itemID], item.status == .downloading else { return }
        states[itemID]?.inFlight[index] = fraction
        item.progress = progress(for: itemID, item: item)
        items[itemID] = item
        publish()
    }

    private func progress(for id: String, item: QueueItem) -> Double {
        guard item.totalTracks > 0 else { return 0 }
        let inFlight = states[id]?.inFlight.values.reduce(0, +) ?? 0
        let done = Double(item.completedTracks + item.failedTracks)
        return min(1, (done + inFlight) / Double(item.totalTracks))
    }

    private func complete(_ id: String, index: Int, file: URL) {
        states[id]?.files[index] = file
        states[id]?.inFlight[index] = nil
        states[id]?.remaining -= 1
        guard var item = items[id] else { return }
        item.completedTracks += 1
        item.destination = item.destination ?? file.deletingLastPathComponent()
        item.progress = progress(for: id, item: item)
        items[id] = item
        publish()
    }

    private func record(_ id: String, index: Int, failure: DownloadFailure, track: Track) {
        states[id]?.inFlight[index] = nil
        states[id]?.remaining -= 1
        states[id]?.failures.append("\(track.id) | \(track.mainArtist.name) - \(track.title) | \(failure.message)")
        guard var item = items[id] else { return }
        item.failedTracks += 1
        item.issues.append(
            TrackIssue(
                id: track.id, title: track.displayTitle, artist: track.mainArtist.name,
                message: failure.message
            )
        )
        item.progress = progress(for: id, item: item)
        items[id] = item
        publish()
    }

    private func finishIfDone(_ id: String) async {
        guard let state = states[id], state.remaining <= 0 else { return }
        await finish(id)
    }

    // MARK: - Completion

    private func finish(_ id: String) async {
        guard var item = items[id] else { return }
        let state = states[id]

        if let state {
            await writeExtras(id: id, item: item, state: state)
        }

        item.status =
            item.failedTracks == 0
            ? .completed : (item.completedTracks == 0 ? .failed : .withErrors)
        item.progress = 1
        items[id] = item
        states[id] = nil
        persist()
        publish()
        pump()
    }

    private func writeExtras(id: String, item: QueueItem, state: ItemState) async {
        let builder = PathBuilder(settings: settings)
        guard let firstTrack = state.tracks.first else { return }
        let destination = builder.paths(for: firstTrack, context: state.context)

        if settings.saveArtwork, !state.collection.cover.isEmpty {
            let name = builder.collectionName(
                settings.coverImageTemplate,
                builder.albumVariables(firstTrack, state.context),
                fallback: "cover"
            )
            for format in settings.localArtworkFormats {
                if let data = await artworkStore.image(
                    state.collection.cover,
                    size: Artwork.clamped(settings.localArtworkSize),
                    format: format
                ) {
                    try? data.write(
                        to: destination.coverDirectory.appending(path: "\(name).\(format.fileExtension)")
                    )
                }
            }
        }

        if settings.saveArtworkArtist, let artistDirectory = destination.artistDirectory,
            !firstTrack.album.mainArtist.picture.isEmpty
        {
            let name = builder.collectionName(
                settings.artistImageTemplate,
                builder.artistVariables(firstTrack, state.context),
                fallback: "folder"
            )
            if let data = await artworkStore.image(
                firstTrack.album.mainArtist.picture,
                size: Artwork.clamped(settings.localArtworkSize),
                format: .jpeg(quality: settings.jpegImageQuality)
            ) {
                try? data.write(to: artistDirectory.appending(path: "\(name).jpg"))
            }
        }

        if settings.createM3U8File, !state.collection.isSingleTrack {
            let name = builder.collectionName(
                settings.playlistFilenameTemplate,
                [
                    "title": item.title, "artist": item.subtitle, "size": String(state.tracks.count),
                    "type": item.link.kind, "id": item.link.identifier,
                    "playlist": state.collection.playlist?.title ?? "",
                    "bitrate": item.format.displayName,
                ],
                fallback: "playlist"
            )
            try? M3U8Writer.write(
                files: state.files,
                to: destination.extrasDirectory.appending(path: "\(name).m3u8"),
                relativeTo: destination.extrasDirectory
            )
        }

        if settings.logErrors, !state.failures.isEmpty {
            try? LogWriter.append(state.failures, to: destination.extrasDirectory.appending(path: "errors.txt"))
        }
        if settings.logSearched, !state.searched.isEmpty {
            try? LogWriter.append(state.searched, to: destination.extrasDirectory.appending(path: "searched.txt"))
        }
    }

    // MARK: - Persistence

    private func persist() {
        try? paths.createDirectories()
        let encoder = JSONEncoder()
        try? encoder.encode(order).write(to: paths.queueDirectory.appending(path: "order.json"), options: .atomic)
        for id in order {
            guard let item = items[id] else { continue }
            try? encoder.encode(item)
                .write(to: paths.queueDirectory.appending(path: "\(id).json"), options: .atomic)
        }
    }

    /// Restores the queue but never auto-starts it, matching deemix.
    public func restore() {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: paths.queueDirectory.appending(path: "order.json")),
            let saved = try? decoder.decode([String].self, from: data)
        else { return }

        for id in saved {
            guard let itemData = try? Data(contentsOf: paths.queueDirectory.appending(path: "\(id).json")),
                var item = try? decoder.decode(QueueItem.self, from: itemData)
            else { continue }
            if item.status.isActive {
                item.status = .queued
                item.progress = 0
                item.completedTracks = 0
                item.failedTracks = 0
                item.issues = []
            }
            items[id] = item
            order.append(id)
        }
        publish()
    }
}
