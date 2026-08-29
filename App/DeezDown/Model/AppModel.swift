import DeezDownKit
import Observation
import SwiftUI

struct Toast: Identifiable, Equatable {
    enum Kind { case info, success, failure }
    let id = UUID()
    var message: String
    var kind: Kind = .info
}

@Observable
final class AppModel {
    enum SignInState: Equatable {
        case signedOut
        case signingIn
        case signedIn(DeezerUser)
        case failed(String)

        var user: DeezerUser? {
            if case .signedIn(let user) = self { return user }
            return nil
        }
    }

    private(set) var signInState: SignInState = .signedOut
    private(set) var queue: [QueueItem] = []
    var settings: DownloadSettings
    var toast: Toast?
    var isRestoring = true

    let session = DeezerSession()
    let player = PreviewPlayer()
    let cache = LibraryCache()

    private let paths = AppPaths()
    private let credentials: CredentialStore
    private let settingsStore: SettingsStore
    private var engine: DownloadEngine?
    private var queueObserver: Task<Void, Never>?

    init() {
        credentials = CredentialStore(paths: paths)
        settingsStore = SettingsStore(paths: paths)
        settings = settingsStore.load()
    }

    var library: DeezerLibrary { DeezerLibrary(session: session) }
    var user: DeezerUser? { signInState.user }
    var isSignedIn: Bool { user != nil }

    var activeDownloads: Int {
        queue.filter { !$0.status.isFinished }.count
    }

    // MARK: - Session

    func restore() async {
        defer { isRestoring = false }
        guard let stored = credentials.arl() else { return }
        await attemptSignIn(arl: stored, remember: false)
    }

    func signIn(arl: String) async {
        await attemptSignIn(arl: arl, remember: true)
    }

    private func attemptSignIn(arl: String, remember: Bool) async {
        signInState = .signingIn
        do {
            let user = try await session.login(arl: arl)
            if remember { try? credentials.save(arl: arl) }
            signInState = .signedIn(user)
            await startEngine()
        } catch {
            signInState = .failed(message(for: error))
        }
    }

    func signOut() {
        queueObserver?.cancel()
        queueObserver = nil
        engine = nil
        queue = []
        cache.invalidate()
        credentials.clear()
        Task { await session.logout() }
        signInState = .signedOut
    }

    private func startEngine() async {
        let engine = DownloadEngine(session: session, settings: settings, paths: paths)
        await engine.restore()
        self.engine = engine
        queueObserver?.cancel()
        queueObserver = Task { [weak self] in
            for await snapshot in await engine.events() {
                guard !Task.isCancelled else { return }
                self?.queue = snapshot
            }
        }
    }

    // MARK: - Settings

    func saveSettings() {
        settings.repair()
        try? settingsStore.save(settings)
        let updated = settings
        Task { await engine?.updateSettings(updated) }
    }

    func resetSettings() {
        settings = DownloadSettings()
        saveSettings()
        show(Toast(message: "Settings reset to defaults", kind: .success))
    }

    // MARK: - Queue

    func enqueue(_ link: DeezerLink, format: TrackFormat? = nil) async {
        await enqueue([link], format: format)
    }

    func enqueue(tracks: [TrackSummary], format: TrackFormat? = nil) async {
        await enqueue(tracks.map(\.link), format: format)
    }

    /// A selection is queued in one go: one round trip, and one message rather than one
    /// per track.
    func enqueue(_ links: [DeezerLink], format: TrackFormat? = nil) async {
        guard !links.isEmpty else { return }
        guard let engine else {
            show(Toast(message: "Sign in to download", kind: .failure))
            return
        }
        do {
            let added = try await engine.enqueue(links, format: format)
            if added.isEmpty {
                show(Toast(message: "Already in the queue"))
            } else {
                show(Toast(message: "Added \(added.count == 1 ? "1 item" : "\(added.count) items")", kind: .success))
            }
        } catch {
            show(Toast(message: message(for: error), kind: .failure))
        }
    }

    func enqueue(pasted text: String) async {
        var links: [DeezerLink] = []
        for candidate in LinkParser.split(text) {
            do {
                links.append(try await LinkParser.resolve(candidate))
            } catch {
                show(Toast(message: message(for: error), kind: .failure))
            }
        }
        await enqueue(links)
    }

    func pause(_ id: String) { Task { await engine?.pause(id) } }
    func resume(_ id: String) { Task { await engine?.resume(id) } }
    func cancel(_ id: String) { Task { await engine?.cancel(id) } }
    func remove(_ id: String) { Task { await engine?.remove(id) } }
    func retry(_ id: String) { Task { await engine?.retry(id) } }
    func cancelAll() { Task { await engine?.cancelAll() } }
    func clearFinished() { Task { await engine?.clearFinished() } }

    func revealDownloads() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: settings.downloadLocation)
    }

    // MARK: - Feedback

    func show(_ toast: Toast) {
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(3))
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }

    /// Every browsing screen loads the same way: reuse what was fetched recently, show a
    /// spinner only when there is nothing on screen yet, and turn a failure into a message.
    func load<Value>(
        _ key: String,
        force: Bool = false,
        into state: (LoadState<Value>) -> Void,
        fetch: () async throws -> Value
    ) async {
        if !force {
            if let cached = cache.value(key, as: Value.self) {
                state(.loaded(cached))
                return
            }
            state(.loading)
        }
        do {
            let fresh = try await fetch()
            cache.store(fresh, for: key)
            state(.loaded(fresh))
        } catch {
            state(.failed(message(for: error)))
        }
    }

    func message(for error: any Error) -> String {
        switch error {
        case let failure as DownloadFailure: failure.message
        case let deezer as DeezerError: deezer.errorDescription ?? "\(deezer)"
        case LinkParseError.notRecognized: "That doesn't look like a Deezer link."
        case LinkParseError.notSupported: "That kind of Deezer link isn't supported."
        case LinkParseError.invalidID(let id): "\"\(id)\" isn't a valid Deezer id."
        default: error.localizedDescription
        }
    }
}
