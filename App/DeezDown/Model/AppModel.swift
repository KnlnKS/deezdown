import DeezDownKit
import SwiftUI

struct Toast: Identifiable {
    enum Kind { case info, success, failure }
    let id = UUID()
    var message: String
    var kind: Kind = .info
}

/// What the sidebar, menus and toolbar show about the queue. Progress changes the queue many
/// times a second but this rarely, so views that need only this don't redraw on every tick.
struct QueueSummary: Equatable {
    var isEmpty = true
    var active = 0
    var canPause = false
    var canResume = false
    var canRetry = false
    var canClear = false

    init(_ queue: [QueueItem] = []) {
        isEmpty = queue.isEmpty
        active = queue.count { !$0.status.isFinished }
        canPause = queue.contains(where: \.canPause)
        canResume = queue.contains(where: \.canResume)
        canRetry = queue.contains(where: \.canRetry)
        canClear = queue.contains(where: \.canClear)
    }
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

    /// A menu command on its way to the window that can act on it. The id makes pressing
    /// the same shortcut twice two separate events.
    struct Command: Equatable {
        enum Kind { case findInSearch, showDownloads }
        var kind: Kind
        var id = UUID()
    }

    private(set) var signInState: SignInState = .signedOut
    private(set) var command: Command?
    private(set) var queue: [QueueItem] = [] {
        didSet {
            let summary = QueueSummary(queue)
            if summary != self.summary { self.summary = summary }
        }
    }
    private(set) var summary = QueueSummary()
    var toast: Toast?
    private(set) var isRestoring = true

    let session = DeezerSession()
    let player = PreviewPlayer()
    let cache = LibraryCache()

    private let paths = AppPaths()
    private let credentials: CredentialStore
    private let settingsStore: SettingsStore
    private var engine: DownloadEngine?
    private var queueObserver: Task<Void, Never>?
    private var settingsWrite: Task<Void, Never>?

    init() {
        credentials = CredentialStore(paths: paths)
        settingsStore = SettingsStore(paths: paths)
        settings = settingsStore.load()
        // Here rather than when a window appears: a window reopened from the Dock would sign in
        // again and start a second engine on the same queue.
        Task {
            if let stored = credentials.arl() { await signIn(arl: stored, remember: false) }
            isRestoring = false
        }
    }

    var library: DeezerLibrary { DeezerLibrary(session: session) }
    var user: DeezerUser? { signInState.user }
    var isSignedIn: Bool { user != nil }

    // MARK: - Session

    func signIn(arl: String, remember: Bool = true) async {
        signInState = .signingIn
        do {
            let user = try await session.login(arl: arl)
            if remember { try? credentials.save(arl: arl) }
            signInState = .signedIn(user)
            await startEngine()
        } catch {
            signInState = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        queueObserver?.cancel()
        queueObserver = nil
        if let engine { Task { await engine.cancelAll() } }
        engine = nil
        queue = []
        cache.invalidate()
        credentials.clear()
        Task { await session.logout() }
        signInState = .signedOut
    }

    private func startEngine() async {
        let engine = DownloadEngine(session: session, settings: settings, queueDirectory: paths.queueDirectory)
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

    /// Settings change on every keystroke in a template field, so each change schedules one
    /// coalesced write. The store and the engine repair what they are given, never the
    /// bindings: clearing a field to retype it would otherwise refill it mid-word.
    var settings: DownloadSettings {
        didSet {
            settingsWrite?.cancel()
            settingsWrite = Task { [settingsStore, engine, settings] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                try? settingsStore.save(settings)
                await engine?.updateSettings(settings)
            }
        }
    }

    func resetSettings() {
        settings = DownloadSettings()
        show(Toast(message: "Settings reset to defaults", kind: .success))
    }

    // MARK: - Queue

    /// A selection is queued in one go: one round trip, and one message rather than one
    /// per track.
    func enqueue(_ links: [DeezerLink]) async {
        guard !links.isEmpty else { return }
        guard let engine else {
            show(Toast(message: "Sign in to download", kind: .failure))
            return
        }
        do {
            let added = try await engine.enqueue(links)
            if added.isEmpty {
                show(Toast(message: "Already in the queue"))
            } else {
                show(Toast(message: "Added \(added.count == 1 ? "1 item" : "\(added.count) items")", kind: .success))
            }
        } catch {
            show(Toast(message: error.localizedDescription, kind: .failure))
        }
    }

    func enqueue(pasted text: String) async {
        let results = await LinkParser.resolveAll(LinkParser.split(text))
        await enqueue(results.compactMap { try? $0.get() })
        // Shown last, so a link that was not understood is not hidden behind "Added".
        let failures = results.compactMap { result -> String? in
            guard case .failure(let error) = result else { return nil }
            return error.localizedDescription
        }
        if let failure = failures.first {
            show(Toast(message: failures.count == 1 ? failure : "\(failures.count) links weren't recognized", kind: .failure))
        }
    }

    func pause(_ id: String) { Task { await engine?.pause(id) } }
    func resume(_ id: String) { Task { await engine?.resume(id) } }
    func cancel(_ id: String) { Task { await engine?.cancel(id) } }
    func remove(_ id: String) { Task { await engine?.remove(id) } }
    func retry(_ id: String) { Task { await engine?.retry(id) } }
    func pauseAll() { Task { await engine?.pauseAll() } }
    func cancelAll() { Task { await engine?.cancelAll() } }
    func resumeAll() { Task { await engine?.resumeAll() } }
    func clearFinished() { Task { await engine?.clearFinished() } }

    func revealDownloads() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: settings.downloadLocation)
    }

    func send(_ command: Command.Kind) {
        self.command = Command(kind: command)
    }

    // MARK: - Feedback

    func show(_ toast: Toast) {
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(3))
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }
}
