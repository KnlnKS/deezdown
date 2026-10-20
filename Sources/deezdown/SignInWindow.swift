import AppKit
import ArgumentParser
import DeezDownKit

extension SignInPage.Method: EnumerableFlag {
    public static func help(for value: Self) -> ArgumentHelp? {
        switch value {
        case .email: "Sign in with an email and password."
        case .google: "Sign in with a Google account."
        }
    }
}

extension SignInPage {
    /// Shows the page in a window of its own until it yields an ARL.
    nonisolated static func run(_ method: Method) async throws -> String {
        guard CGSessionCopyCurrentDictionary() != nil else {
            throw ValidationError("There's no display to sign in on. Pass --arl instead.")
        }
        // AppKit's event loop has to start from the main run loop. Started from a main actor hop,
        // a job on the main queue, it would hold back every later job, WebKit's included.
        let arl = await withCheckedContinuation { continuation in
            RunLoop.main.perform {
                MainActor.assumeIsolated { continuation.resume(returning: show(method)) }
            }
        }
        guard let arl else {
            printError("The sign-in window was closed.")
            throw ExitCode.failure
        }
        return arl
    }

    private static func show(_ method: Method) -> String? {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        var arl: String?
        window.contentView = SignInPage(method) { [weak window] in
            arl = $0
            window?.close()
        }
        window.title = title
        window.isReleasedWhenClosed = false
        window.collectionBehavior = .moveToActiveSpace
        window.center()
        let closing = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NSApp.stop(nil)
                // Stopping waits for an event to finish, and the page closing the window sends none.
                NSApp.postEvent(
                    .otherEvent(
                        with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                        context: nil, subtype: 0, data1: 0, data2: 0
                    )!, atStart: true
                )
            }
        }
        defer { NotificationCenter.default.removeObserver(closing) }
        // A terminal keeps focus unless it hands it over, so the window comes forward regardless.
        window.makeKey()
        window.orderFrontRegardless()
        app.activate()
        app.run()
        return arl
    }
}
