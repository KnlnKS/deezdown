import Foundation
import Synchronization

public actor DownloadEngine {
    private struct TrackJob: Sendable {
        var itemID: String
        var index: Int
        var outcome: Result<ResolvedMedia, DownloadFailure>
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
    private let encoder = JSONEncoder()

    private var settings: DownloadSettings
    private var items: [String: QueueItem] = [:]
    private var order: [String] = []
    private var states: [String: ItemState] = [:]
    private var jobs: [TrackJob] = []
    private var heldJobs: [TrackJob] = []
    private var activeWorkers = 0
    private var directorRunning = false
    private var canceled: Set<String> = []
    private var lastProgressPublish: ContinuousClock.Instant?
    private var observers: [UUID: AsyncStream<[QueueItem]>.Continuation] = [:]

    public init(session: DeezerSession, settings: DownloadSettings, paths: AppPaths = AppPaths()) {
        self.session = session
        self.settings = settings
        self.paths = paths
        try? paths.createDirectories()
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
        try await enqueue([link], format: requested)
    }

    @discardableResult
    public func enqueue(_ links: [DeezerLink], format requested: TrackFormat? = nil) async throws -> [String] {
        guard let user = await session.user else { throw DeezerError.notLoggedIn }
        var format = requested ?? settings.maxBitrate
        if !user.canStream(format) {
            guard settings.fallbackBitrate else { throw DownloadFailure(.wrongLicense) }
            format = user.highestAvailableFormat
        }

        var pending: [PendingLink] = []
        for link in links { pending += try await expand(link) }

        var added: [String] = []
        for entry in pending {
            let id = QueueItem.identifier(for: entry.link, format: format)
            guard items[id] == nil else { continue }
            // Queue ids are deterministic, so an id removed earlier must lose its tombstone
            // or the fresh item would be treated as canceled the moment it resolved.
            canceled.remove(id)
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
        persist(added)
        persistOrder()
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

    /// Artist links become one queue entry per album, named from the discography listing.
    /// Reading each album's tracks here would double every request the queue is about to
    /// make anyway.
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
        return try await resolver.artistAlbums(id, tab: tab).map {
            PendingLink(
                link: .album($0.id), title: $0.title, subtitle: $0.artist,
                cover: $0.cover, trackCount: $0.trackCount
            )
        }
    }

    public func cancel(_ id: String) {
        guard var item = items[id] else { return }
        canceled.insert(id)
        jobs.removeAll { $0.itemID == id }
        heldJobs.removeAll { $0.itemID == id }
        if !item.status.isFinished {
            item.status = .canceled
            items[id] = item
        }
        states[id] = nil
        persist(id)
        publish()
        pump()
    }

    public func cancelAll() {
        for id in order where !(items[id]?.status.isFinished ?? true) { canceled.insert(id) }
        jobs.removeAll()
        heldJobs.removeAll()
        for id in order {
            guard var item = items[id], !item.status.isFinished else { continue }
            item.status = .canceled
            items[id] = item
        }
        states.removeAll()
        persist(order)
        publish()
    }

    public func remove(_ id: String) {
        canceled.insert(id)
        jobs.removeAll { $0.itemID == id }
        heldJobs.removeAll { $0.itemID == id }
        items[id] = nil
        states[id] = nil
        order.removeAll { $0 == id }
        try? FileManager.default.removeItem(at: queueFile(id))
        persistOrder()
        publish()
    }

    /// Clears what needs no attention; items that failed stay so their errors can be read.
    public func clearFinished() {
        let finished = Set(order.filter { [.completed, .canceled].contains(items[$0]?.status) })
        guard !finished.isEmpty else { return }
        for id in finished {
            items[id] = nil
            states[id] = nil
            try? FileManager.default.removeItem(at: queueFile(id))
        }
        order.removeAll { finished.contains($0) }
        persistOrder()
        publish()
    }

    /// Pausing holds an item's remaining tracks aside; anything already in flight is allowed
    /// to finish rather than throwing away a part-downloaded file.
    public func pause(_ id: String) {
        guard var item = items[id], item.canPause else { return }
        heldJobs.append(contentsOf: jobs.filter { $0.itemID == id })
        jobs.removeAll { $0.itemID == id }
        item.status = .paused
        items[id] = item
        persist(id)
        publish()
    }

    public func resume(_ id: String) {
        guard var item = items[id], item.status == .paused else { return }
        let released = heldJobs.filter { $0.itemID == id }
        heldJobs.removeAll { $0.itemID == id }
        jobs.append(contentsOf: released)
        item.status = states[id] == nil && released.isEmpty ? .queued : .downloading
        items[id] = item
        persist(id)
        publish()
        pump()
        Task { await finishIfDone(id) }
    }

    public func retry(_ id: String) {
        guard var item = items[id], item.canRetry else { return }
        canceled.remove(id)
        heldJobs.removeAll { $0.itemID == id }
        item.status = .queued
        item.completedTracks = 0
        item.failedTracks = 0
        item.progress = 0
        item.issues = []
        items[id] = item
        states[id] = nil
        persist(id)
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
                today: .today
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
            if item.status != .paused { item.status = .downloading }
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
                    enqueueJob(TrackJob(itemID: id, index: index, outcome: .success(media)))
                case .failure(let failure):
                    enqueueJob(TrackJob(itemID: id, index: index, outcome: .failure(failure)))
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
        persist(id)
        publish()
    }

    private func enqueueJob(_ job: TrackJob) {
        if items[job.itemID]?.status == .paused {
            heldJobs.append(job)
        } else {
            jobs.append(job)
        }
    }

    // MARK: - Track execution

    private func perform(_ job: TrackJob) async {
        guard !canceled.contains(job.itemID), let state = states[job.itemID] else { return }
        let track = state.tracks[job.index]

        let media: ResolvedMedia
        switch job.outcome {
        case .success(let resolved): media = resolved
        case .failure(let failure):
            record(job.itemID, index: job.index, failure: failure, track: track)
            await finishIfDone(job.itemID)
            return
        }

        let builder = PathBuilder(settings: settings)
        let destination = builder.paths(for: track, context: state.context)
        let base = destination.directory.appending(path: destination.filename)
        let decision = OverwritePolicy.decide(
            base: base, format: media.format, duration: track.duration, mode: settings.overwriteFile
        )

        let file: URL
        let needsAudio: Bool
        switch decision {
        // A file that is already there needs no BPM, no lyrics and no request.
        case .skip(let existing):
            complete(job.itemID, index: job.index, file: existing)
            await finishIfDone(job.itemID)
            return
        case .tagOnly(let existing): (file, needsAudio) = (existing, false)
        case .download(let target): (file, needsAudio) = (target, true)
        }

        let needsLyrics =
            settings.tags.lyrics || settings.tags.syncedLyrics || settings.syncedLyrics
        async let extras = trackExtras(for: track, needsLyrics: needsLyrics)

        if needsAudio {
            let itemID = job.itemID
            let index = job.index
            let lastReported = Mutex<Double>(0)
            do {
                try await downloader.download(media, to: file) { [weak self] written, total in
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
            } catch {
                _ = await extras
                record(
                    job.itemID, index: job.index,
                    failure: error as? DownloadFailure ?? DownloadFailure(.network(error.localizedDescription)),
                    track: track
                )
                await finishIfDone(job.itemID)
                return
            }
        }

        var enriched = track
        let (bpm, lyrics) = await extras
        enriched.bpm = bpm ?? enriched.bpm
        enriched.lyrics = lyrics ?? enriched.lyrics

        let artwork = states[job.itemID]?.artwork
        do {
            try Tagger.tag(
                enriched, format: media.format, at: file, artwork: artwork, settings: settings
            )
            if settings.finderArtwork, let artwork, FinderIcon.isNeeded(for: media.format) {
                await FinderIcon.apply(artwork, to: file)
            }
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

    /// Eight tracks reporting every percent is a few hundred snapshots a second, and the
    /// screen can show one per frame. Whatever a tick drops, the next one carries, and
    /// finishing a track always publishes.
    private func report(itemID: String, index: Int, fraction: Double) {
        guard states[itemID] != nil, var item = items[itemID], item.status == .downloading else { return }
        states[itemID]?.inFlight[index] = fraction
        item.progress = progress(for: itemID, item: item)
        items[itemID] = item

        let now = ContinuousClock.now
        if let last = lastProgressPublish, now - last < .milliseconds(50) { return }
        lastProgressPublish = now
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

        guard item.status != .paused else { return }
        item.status =
            item.failedTracks == 0
            ? .completed : (item.completedTracks == 0 ? .failed : .withErrors)
        item.progress = 1
        items[id] = item
        states[id] = nil
        persist(id)
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

    private var orderFile: URL { paths.queueDirectory.appending(path: "order.json") }

    private func queueFile(_ id: String) -> URL {
        paths.queueDirectory.appending(path: "\(id).json")
    }

    /// Only what changed goes to disk. Rewriting every entry on every event put one file
    /// write per queued item in the path of each finished track.
    private func persist(_ ids: some Sequence<String>) {
        for id in ids {
            guard let item = items[id] else { continue }
            try? encoder.encode(item).write(to: queueFile(id), options: .atomic)
        }
    }

    private func persist(_ id: String) {
        persist(CollectionOfOne(id))
    }

    private func persistOrder() {
        try? encoder.encode(order).write(to: orderFile, options: .atomic)
    }

    /// Restores the queue but never auto-starts it, matching deemix.
    public func restore() {
        items.removeAll()
        order.removeAll()

        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: orderFile),
            let saved = try? decoder.decode([String].self, from: data)
        else { return }

        for id in saved {
            guard let itemData = try? Data(contentsOf: queueFile(id)),
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
