import ArgumentParser
import DeezDownKit
import Foundation

@main
struct Deezdown: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deezdown",
        abstract: "Download music from Deezer.",
        version: "0.1.0",
        subcommands: [Download.self, Search.self, Login.self, Logout.self, Config.self],
        defaultSubcommand: Download.self
    )
}

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Keep configuration in ./config instead of Application Support.")
    var portable = false

    var paths: AppPaths { AppPaths(portable: portable) }

    /// Signs in with the ARL given, remembering it once it works, else with the stored one.
    func signIn(arl given: String?) async throws -> (DeezerSession, DeezerUser) {
        let credentials = CredentialStore(paths: paths)
        let session = DeezerSession()
        if let given {
            let user = try await session.login(arl: given)
            try await credentials.save(arl: given)
            return (session, user)
        }
        guard let stored = await credentials.arl() else {
            printError("Not signed in. Run `deezdown login` first.")
            throw ExitCode.failure
        }
        return (session, try await session.login(arl: stored))
    }
}

struct Login: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Sign in to Deezer for future runs.")

    @OptionGroup var options: GlobalOptions

    @Flag var method: SignInPage.Method = .email

    @Option(name: .long, help: "Sign in with this ARL cookie value instead.")
    var arl: String?

    func run() async throws {
        let arl = if let arl { arl } else { try await SignInPage.run(method) }
        let (_, user) = try await options.signIn(arl: arl)
        print("Signed in as \(user.name) (\(user.country), \(user.plan.lowercased())).")
    }
}

struct Logout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Forget the stored Deezer sign-in.")

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        try await CredentialStore(paths: options.paths).clear()
        print("Signed out.")
    }
}

struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show or change persistent download settings.",
        subcommands: [Get.self, Set.self, Reset.self]
    )

    @OptionGroup var options: GlobalOptions

    func run() throws {
        let settings = SettingsStore(paths: options.paths).load()
        print("Config:    \(options.paths.configDirectory.path(percentEncoded: false))")
        print("Downloads: \(settings.downloadLocation)")
        print("Quality:   \(settings.maxBitrate.displayName)")
        print("Use `deezdown config get` to list every setting.")
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print one setting or the complete configuration as JSON.")
        @OptionGroup var options: GlobalOptions
        @Argument(help: "Setting name, such as tracknameTemplate or tags.lyrics.") var key: String?

        func run() throws {
            let value = try ConfigurationValue(SettingsStore(paths: options.paths).load())
            print(try value.render(key: key))
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change and save a setting.")
        @OptionGroup var options: GlobalOptions
        @Argument(help: "Setting name, such as albumTracknameTemplate or tags.artist.") var key: String
        @Argument(help: "New value. Booleans use true or false; enum values use their stored names.") var value: String

        func run() throws {
            let store = SettingsStore(paths: options.paths)
            let settings = try ConfigurationValue(store.load()).setting(key, to: value)
            try store.save(settings)
            print(try ConfigurationValue(settings).render(key: key))
        }
    }

    struct Reset: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Restore all default settings.")
        @OptionGroup var options: GlobalOptions

        func run() throws {
            try SettingsStore(paths: options.paths).save(DownloadSettings())
            print("Settings restored to defaults.")
        }
    }
}

struct Download: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Download tracks, albums, playlists or artists.")

    @OptionGroup var options: GlobalOptions

    @Argument(help: "One or more Deezer links, or files that list them.")
    var links: [String] = []

    @Option(name: [.short, .long], help: "Download into this folder instead of the configured one.")
    var path: String?

    @Option(name: [.short, .long], help: "Quality: flac, 320, 128, 360_hq, 360_mq, 360_lq.")
    var bitrate: String?

    @Option(name: .long, help: "Sign in with this ARL and remember it.")
    var arl: String?

    @Option(name: [.customShort("j"), .long], help: "Number of tracks to download at once.")
    var concurrency: Int?

    func validate() throws {
        guard !links.isEmpty else {
            throw ValidationError("Pass at least one Deezer link.")
        }
        if let bitrate, TrackFormat.parse(bitrate) == nil {
            printError("Unknown bitrate \"\(bitrate)\". Use one of:")
            for (_, names) in TrackFormat.aliases { printError("  " + names.joined(separator: " | ")) }
            throw ExitCode.failure
        }
    }

    func run() async throws {
        let (session, _) = try await options.signIn(arl: arl)
        var settings = SettingsStore(paths: options.paths).load()
        if let path { settings.downloadLocation = URL(fileURLWithPath: path).standardizedFileURL.path }
        if let concurrency { settings.queueConcurrency = concurrency }

        let format = bitrate.flatMap(TrackFormat.parse)
        let engine = await DownloadEngine(session: session, settings: settings)

        // As in deemix, a file stands for the links written in it.
        let listed = try links.flatMap { argument in
            FileManager.default.fileExists(atPath: argument)
                ? LinkParser.split(try String(contentsOfFile: argument, encoding: .utf8)) : LinkParser.split(argument)
        }
        var parsed: [DeezerLink] = []
        for (link, result) in zip(listed, await LinkParser.resolveAll(listed)) {
            switch result {
            case .success(let resolved): parsed.append(resolved)
            case .failure(let error):
                printError("Skipping \(link): \(error.localizedDescription)")
            }
        }
        guard try await engine.enqueue(parsed, format: format).count > 0 else { throw ExitCode.failure }

        let reporter = ProgressReporter()
        for await queue in await engine.events() {
            reporter.render(queue)
            if queue.allSatisfy(\.status.isFinished) { break }
        }

        let queue = await engine.queue
        reporter.summarize(queue)
        if queue.contains(where: { $0.status == .failed }) { throw ExitCode.failure }
    }
}

/// Kept off standard output, which may be piped.
func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
