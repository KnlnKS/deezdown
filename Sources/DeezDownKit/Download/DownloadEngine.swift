import Foundation
import Synchronization

public actor DownloadEngine {
    private struct TrackJob: Sendable {
        var itemID: String
        var run: UUID
        var index: Int
        var media: ResolvedMedia
    }

    private struct ItemState {
        var collection: ResolvedCollection
        var context: DownloadContext
        var extras: CollectionExtras
        var inFlight: [Int: Double] = [:]
        var remaining: Int
        /// Playlist entries carry only an album's ID and title; deemix fetches the rest per track.
        var albums: [String: Task<Album?, Never>] = [:]
        /// Tracks waiting for a worker, which go on waiting while the item is paused. A slice, so a
        /// worker takes the next one without shifting a playlist's worth behind it.
        var pending: ArraySlice<TrackJob> = []
    }

    private let session: DeezerSession
    private let queueDirectory: URL?
    private let artworkStore = ArtworkStore()
    private let downloader = MediaDownloader()
    private let encoder = JSONEncoder()

    private var settings: DownloadSettings
    private var items: [String: QueueItem] = [:]
    private var order: [String] = []
    private var states: [String: ItemState] = [:]
    private var activeWorkers = 0
    private var directorRunning = false
    /// Each preparation of an item is a run. Cancelling, removing or retrying an item ends its
    /// run, so work that wakes from an await to find another run has been handed on.
    private var runs: [String: UUID] = [:]
    private var transfers: [String: [Int: Task<Int64, any Error>]] = [:]
    private var lastProgressPublish: ContinuousClock.Instant?
    private var observers: [UUID: AsyncStream<[QueueItem]>.Continuation] = [:]

    /// Without a queue directory nothing is persisted, so a one-shot run such as the CLI
    /// cannot overwrite the queue the app restores.
    public init(session: DeezerSession, settings: DownloadSettings, queueDirectory: URL? = nil) {
        self.session = session
        self.settings = settings
        self.settings.repair()
        self.queueDirectory = queueDirectory
        if let queueDirectory {
            try? FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        }
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

    /// Settings arrive as typed, so the engine makes them usable itself.
    public func updateSettings(_ newValue: DownloadSettings) {
        settings = newValue
        settings.repair()
    }

    // MARK: - Queueing

    @discardableResult
    public func enqueue(_ links: [DeezerLink], format requested: TrackFormat? = nil) async throws -> [String] {
        guard let user = await session.user else { throw DeezerError.notLoggedIn }
        var format = requested ?? settings.maxBitrate
        if !user.canStream(format) {
            guard settings.fallbackBitrate else { throw DownloadFailure(.wrongLicense) }
            format = user.highestAvailableFormat
        }

        var expanded: [QueueItem] = []
        for link in links { expanded += try await expand(link, format: format) }

        var added: [String] = []
        for item in expanded where items[item.id] == nil {
            items[item.id] = item
            order.append(item.id)
            added.append(item.id)
        }
        guard !added.isEmpty else { return [] }
        persist(added)
        persistOrder()
        publish()
        pump()
        return added
    }

    /// Artist links become one queue entry per album, named from the discography listing.
    /// Reading each album's tracks here would double every request the queue is about to
    /// make anyway.
    private func expand(_ link: DeezerLink, format: TrackFormat) async throws -> [QueueItem] {
        guard case .artist(let id, let tab) = link else {
            return [
                QueueItem(
                    link: link, title: link.placeholderTitle, subtitle: "Looking up tracks…",
                    cover: Artwork(md5: "", kind: .cover), format: format
                )
            ]
        }
        async let artistTask = session.artistData(id: id)
        let albums = try await LinkResolver(session: session).artistAlbums(id, tab: tab)
        let artist = (try? await artistTask).map(ArtistRef.init(gateway:))
        return albums.map {
            QueueItem(
                link: .album($0.id), title: $0.title, subtitle: $0.artist, cover: $0.cover, format: format,
                totalTracks: $0.trackCount, rootArtist: artist
            )
        }
    }

    public func cancel(_ id: String) {
        cancel(Set([id]))
    }

    public func cancelAll() {
        cancel(Set(order))
    }

    private func cancel(_ ids: Set<String>) {
        let unfinished = ids.filter { items[$0]?.status.isFinished == false }
        guard !unfinished.isEmpty else { return }
        stopWork(for: unfinished)
        for id in unfinished { items[id]?.status = .canceled }
        persist(unfinished)
        publish()
        pump()
    }

    public func remove(_ id: String) {
        stopWork(for: [id])
        discard([id])
    }

    public func clearFinished() {
        discard(Set(order.filter { items[$0]?.canClear == true }))
    }

    /// Drops waiting tracks with the items' state and aborts transfers in flight, so nothing more
    /// lands on disk for these items.
    private func stopWork(for ids: Set<String>) {
        for id in ids {
            runs[id] = nil
            states.removeValue(forKey: id)?.albums.values.forEach { $0.cancel() }
            transfers.removeValue(forKey: id)?.values.forEach { $0.cancel() }
        }
    }

    private func discard(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            items[id] = nil
            if let file = queueFile(id) { try? FileManager.default.removeItem(at: file) }
        }
        order.removeAll { ids.contains($0) }
        persistOrder()
        publish()
    }

    public func pause(_ id: String) {
        pause(Set([id]))
    }

    public func pauseAll() {
        pause(Set(order))
    }

    /// Pausing stops the tracks in flight too, which start over on resume: a whole album is often
    /// in flight at once, so letting them finish would not pause it.
    private func pause(_ ids: Set<String>) {
        let pausable = ids.filter { items[$0]?.canPause == true }
        guard !pausable.isEmpty else { return }
        for id in pausable {
            transfers[id]?.values.forEach { $0.cancel() }
            states[id]?.inFlight.removeAll()
            guard var item = items[id] else { continue }
            item.status = .paused
            item.progress = progress(for: id, item: item)
            items[id] = item
        }
        persist(pausable)
        publish()
    }

    public func resume(_ id: String) {
        resume(Set([id]))
    }

    public func resumeAll() {
        resume(Set(order))
    }

    private func resume(_ ids: Set<String>) {
        let paused = ids.filter { items[$0]?.status == .paused }
        guard !paused.isEmpty else { return }
        for id in paused { items[id]?.status = states[id] == nil ? .queued : .downloading }
        persist(paused)
        publish()
        pump()
    }

    public func retry(_ id: String) {
        guard var item = items[id], item.canRetry else { return }
        item.reset(to: .queued)
        items[id] = item
        persist([id])
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
        guard readyCount < settings.queueConcurrency * 4 else { return }
        directorRunning = true
        Task { await runDirector() }
    }

    private func runDirector() async {
        defer { directorRunning = false }
        while readyCount < settings.queueConcurrency * 4 {
            guard let id = order.first(where: { items[$0]?.status == .queued }) else { return }
            await prepare(id)
            startWorkersIfNeeded()
        }
    }

    private func startWorkersIfNeeded() {
        let wanted = min(settings.queueConcurrency, activeWorkers + readyCount)
        while activeWorkers < wanted {
            activeWorkers += 1
            Task { await runWorker() }
        }
    }

    private func runWorker() async {
        while let job = nextJob() { await perform(job) }
        activeWorkers -= 1
        pump()
    }

    private var readyCount: Int {
        order.reduce(0) { count, id in
            items[id]?.status == .downloading ? count + (states[id]?.pending.count ?? 0) : count
        }
    }

    /// The queue's order is the download order.
    private func nextJob() -> TrackJob? {
        for id in order where items[id]?.status == .downloading {
            if let job = states[id]?.pending.popFirst() { return job }
        }
        return nil
    }

    // MARK: - Preparation

    private func prepare(_ id: String) async {
        guard var item = items[id], item.status == .queued else { return }
        item.status = .resolving
        items[id] = item
        publish()

        let run = UUID()
        runs[id] = run
        do {
            let collection = try await LinkResolver(session: session).resolve(item.link)
            guard runs[id] == run else { return }

            let count = collection.tracks.count
            let context = DownloadContext(
                playlist: collection.playlist,
                isSingleTrackDownload: collection.isSingleTrack,
                rootArtist: item.rootArtist ?? collection.rootArtist,
                format: item.format
            )
            // The albums start loading while the streams resolve; cancelling drops them with the state.
            states[id] = ItemState(
                collection: collection,
                context: context,
                extras: CollectionExtras(trackCount: count),
                remaining: count,
                albums: collection.playlist == nil ? [:] : prefetchAlbums(of: collection.tracks)
            )

            // As in deemix, a search for a stand-in uses the metadata as Deezer gave it.
            let resolvedMedia = try await MediaResolver(session: session, settings: settings)
                .resolve(collection.tracks, format: item.format)
            guard runs[id] == run else { return }

            item = items[id] ?? item
            item.title = collection.title
            item.subtitle = collection.subtitle
            item.cover = collection.cover
            item.totalTracks = count
            if item.status != .paused { item.status = .downloading }
            items[id] = item

            var pending: [TrackJob] = []
            for (index, outcome) in resolvedMedia.enumerated() {
                switch outcome {
                case .success(let media):
                    if media.track.searched {
                        states[id]?.extras.searched.append("\(media.track.mainArtist.name) - \(media.track.title)")
                    }
                    pending.append(TrackJob(itemID: id, run: run, index: index, media: media))
                case .failure(let failure):
                    record(id, index: index, failure: failure, track: collection.tracks[index].applying(settings))
                }
            }
            states[id]?.pending = pending[...]
            await finishIfDone(id)
        } catch {
            guard runs[id] == run else { return }
            stopWork(for: [id])
            item = items[id] ?? item
            item.status = .failed
            item.issues = [
                TrackIssue(
                    id: item.id, title: item.title, artist: item.subtitle,
                    message: error.localizedDescription
                )
            ]
            items[id] = item
        }
        persist([id])
        publish()
    }

    /// Each album once, in track order and a few at a time, so the workers seldom wait and the
    /// public API's rate limit is shared rather than swamped.
    private func prefetchAlbums(of tracks: [Track]) -> [String: Task<Album?, Never>] {
        let width = 6
        var seen = Set<String>()
        let ids = tracks.map(\.album.id).filter { $0 != "0" && seen.insert($0).inserted }
        var tasks: [Task<Album?, Never>] = []
        for (index, id) in ids.enumerated() {
            let earlier = index >= width ? tasks[index - width] : nil
            tasks.append(Task { [session] in
                _ = await earlier?.value
                return try? await session.enrichedAlbum(id: id)
            })
        }
        return Dictionary(uniqueKeysWithValues: zip(ids, tasks))
    }

    // MARK: - Track execution

    private func isCurrent(_ job: TrackJob) -> Bool { runs[job.itemID] == job.run }

    private func perform(_ job: TrackJob) async {
        // Only the context: a copy of the whole state held across the awaits below would make
        // every track's bookkeeping copy the item's arrays instead of writing in place.
        guard isCurrent(job), let context = states[job.itemID]?.context else { return }
        let media = job.media
        var track = media.track
        if let pending = states[job.itemID]?.albums[track.album.id], let album = await pending.value {
            track.album = album
        }
        track = track.applying(settings)

        let builder = PathBuilder(settings: settings)
        let namesBPM = track.bpm == 0 && builder.filenameTemplate(for: context).contains("%bpm%")
        if namesBPM { track.bpm = await session.publicTrackBPM(id: track.id) ?? 0 }
        guard isCurrent(job) else { return }
        guard items[job.itemID]?.status != .paused else {
            states[job.itemID]?.pending.append(job)
            return
        }

        let destination = builder.paths(for: track, context: context)
        let base = destination.directory.appending(path: destination.filename)
        let lrcFile = base.appendingPathExtension("lrc")
        let decision = OverwritePolicy.decide(
            base: base, format: media.format, duration: track.duration, mode: settings.overwriteFile
        )

        let file: URL
        let needsAudio: Bool
        switch decision {
        // A file that is already there needs no BPM, no cover and, unless its .lrc is missing,
        // no lyrics.
        case .skip(let existing):
            let writesLRC =
                settings.syncedLyrics && !FileManager.default.fileExists(atPath: lrcFile.path(percentEncoded: false))
            let found = writesLRC ? await lyrics(for: track) : nil
            guard isCurrent(job) else { return }
            if let found { try? LRCWriter.write(found, to: lrcFile, overwrite: false) }
            states[job.itemID]?.extras.noteArtwork(
                for: track, at: destination, context: context, settings: settings)
            complete(job.itemID, index: job.index, file: existing)
            await finishIfDone(job.itemID)
            return
        case .tagOnly(let existing): (file, needsAudio) = (existing, false)
        case .download(let target): (file, needsAudio) = (target, true)
        }

        // Fetched while the audio streams.
        let named = track
        let needsLyrics = settings.tags.lyrics || settings.tags.syncedLyrics || settings.syncedLyrics
        async let bpm = settings.tags.bpm && named.bpm == 0 && !namesBPM ? session.publicTrackBPM(id: named.id) : nil
        async let lyrics = needsLyrics ? lyrics(for: named) : nil
        async let artwork =
            settings.tags.cover
            ? artworkStore.image(
                named.album.cover, size: settings.embeddedArtworkSize, format: settings.embeddedArtworkFormat)
            : nil

        if needsAudio {
            let lastReported = Mutex<Double>(0)
            let onProgress: @Sendable (Int64, Int64) -> Void = { [weak self] written, total in
                guard total > 0 else { return }
                let fraction = min(1, Double(written) / Double(total))
                let shouldReport = lastReported.withLock { last -> Bool in
                    guard fraction - last >= 0.01 || fraction >= 1 else { return false }
                    last = fraction
                    return true
                }
                guard shouldReport, let self else { return }
                Task { await self.report(job, fraction: fraction) }
            }
            let transfer = Task { [downloader] in
                try await downloader.download(media, to: file, onProgress: onProgress)
            }
            transfers[job.itemID, default: [:]][job.index] = transfer
            let outcome = await transfer.result
            // A cancelled item has already dropped its transfers, and a retry may have begun new ones.
            guard isCurrent(job) else { return }
            transfers[job.itemID]?[job.index] = nil
            if case .failure(let error) = outcome {
                // Only a pause cancels a transfer whose run is still current; the track waits for resume.
                if error is CancellationError {
                    states[job.itemID]?.pending.append(job)
                    return
                }
                record(job.itemID, index: job.index, failure: DownloadFailure(error), track: track)
                await finishIfDone(job.itemID)
                return
            }
        }

        track.bpm = await bpm ?? track.bpm
        track.lyrics = await lyrics ?? track.lyrics
        let cover = await artwork
        guard isCurrent(job) else { return }

        do {
            try await Tagger.tag(track, format: media.format, at: file, artwork: cover, settings: settings)
            if settings.finderArtwork, let cover, FinderIcon.isNeeded(for: media.format) {
                await FinderIcon.apply(cover, to: file)
            }
        } catch {
            states[job.itemID]?.extras.fail(track, "Tagging failed: \(error.localizedDescription)")
        }
        guard isCurrent(job) else { return }

        if settings.syncedLyrics, let lyrics = track.lyrics, !lyrics.lines.isEmpty {
            try? LRCWriter.write(
                lyrics, to: lrcFile,
                overwrite: settings.overwriteFile == .overwrite || settings.overwriteFile == .tagsOnly
            )
        }

        states[job.itemID]?.extras.noteArtwork(for: track, at: destination, context: context, settings: settings)
        complete(job.itemID, index: job.index, file: file)
        await finishIfDone(job.itemID)
    }

    private func lyrics(for track: Track) async -> Lyrics? {
        if let lyrics = track.lyrics { return lyrics }
        guard track.lyricsID != "0" else { return nil }
        return (try? await session.lyrics(trackID: track.id)).map(Lyrics.init(results:))
    }

    /// Eight tracks reporting every percent is a few hundred snapshots a second, and the
    /// screen can show one per frame. Whatever a tick drops, the next one carries, and
    /// finishing a track always publishes.
    private func report(_ job: TrackJob, fraction: Double) {
        guard isCurrent(job), var item = items[job.itemID], item.status == .downloading else { return }
        states[job.itemID]?.inFlight[job.index] = fraction
        item.progress = progress(for: job.itemID, item: item)
        items[job.itemID] = item

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
        states[id]?.extras.files[index] = file
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
        states[id]?.extras.fail(track, failure.localizedDescription)
        guard var item = items[id] else { return }
        item.failedTracks += 1
        item.issues.append(
            TrackIssue(
                id: track.id, title: track.title, artist: track.mainArtist.name,
                message: failure.localizedDescription
            )
        )
        item.progress = progress(for: id, item: item)
        items[id] = item
        publish()
    }

    // MARK: - Completion

    /// An item is done once every track is, paused or not: pausing holds back tracks that
    /// have not started, and there are none left. Taking the state first means a second
    /// caller finds nothing to finish, so extras are written once.
    private func finishIfDone(_ id: String) async {
        guard let state = states[id], state.remaining <= 0 else { return }
        stopWork(for: [id])
        if let item = items[id] {
            await state.extras.write(
                for: item, from: state.collection, context: state.context, settings: settings, artworkStore: artworkStore
            )
        }

        guard var item = items[id], !item.status.isFinished else { return }
        item.status =
            item.failedTracks == 0
            ? .completed : (item.completedTracks == 0 ? .failed : .withErrors)
        item.progress = 1
        items[id] = item
        persist([id])
        publish()
        pump()
    }

    // MARK: - Persistence

    private var orderFile: URL? { queueDirectory?.appending(path: "order.json") }

    private func queueFile(_ id: String) -> URL? {
        queueDirectory?.appending(path: "\(id).json")
    }

    /// Only what changed goes to disk, so a finished track costs one write rather than one per
    /// queued item.
    private func persist(_ ids: some Sequence<String>) {
        for id in ids {
            guard let item = items[id], let file = queueFile(id) else { continue }
            try? encoder.encode(item).write(to: file, options: .atomic)
        }
    }

    private func persistOrder() {
        guard let orderFile else { return }
        try? encoder.encode(order).write(to: orderFile, options: .atomic)
    }

    /// Restores the queue without starting it, as deemix does. Anything unfinished comes
    /// back paused, so it reads as waiting on the user and Resume picks it up.
    public func restore() {
        items.removeAll()
        order.removeAll()

        let decoder = JSONDecoder()
        guard let orderFile, let data = try? Data(contentsOf: orderFile),
            let saved = try? decoder.decode([String].self, from: data)
        else { return }

        for id in saved {
            guard let file = queueFile(id), let itemData = try? Data(contentsOf: file),
                var item = try? decoder.decode(QueueItem.self, from: itemData)
            else { continue }
            if !item.status.isFinished { item.reset(to: .paused) }
            items[id] = item
            order.append(id)
        }
        publish()
    }
}
