import ArgumentParser
import DeezDownKit
import Foundation

@main
struct Deezdown: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deezdown",
        abstract: "Download music from Deezer.",
        version: DeezDown.version,
        subcommands: [Download.self, Search.self, Login.self, Logout.self, Config.self],
        defaultSubcommand: Download.self
    )
}

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Keep configuration in ./config instead of Application Support.")
    var portable = false

    var paths: AppPaths { AppPaths(portable: portable) }

    /// Signs in with the ARL given, else the stored one, else one typed at the terminal. An ARL
    /// that wasn't stored is remembered once it works.
    func signIn(arl given: String?) async throws -> (DeezerSession, DeezerUser) {
        let credentials = CredentialStore(paths: paths)
        let session = DeezerSession()
        if given == nil, let stored = credentials.arl(), let user = try? await session.login(arl: stored) {
            return (session, user)
        }
        let arl = try given ?? Self.typedARL()
        let user = try await session.login(arl: arl)
        try credentials.save(arl: arl)
        return (session, user)
    }

    private static func typedARL() throws -> String {
        guard isatty(FileHandle.standardInput.fileDescriptor) == 1 else {
            FileHandle.standardError.write(
                Data(
                    """
                    Not signed in. Run `deezdown login --arl <ARL>`, or run deezdown from a \
                    terminal to be prompted.\n
                    """.utf8))
            throw ExitCode.failure
        }
        FileHandle.standardError.write(Data("Enter your ARL: ".utf8))
        guard let typed = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !typed.isEmpty else {
            throw ValidationError("No ARL entered.")
        }
        return typed
    }
}

struct Login: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Store a Deezer ARL for future runs.")

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "The ARL cookie value. Omit to be prompted.")
    var arl: String?

    func run() async throws {
        let (_, user) = try await options.signIn(arl: arl)
        print("Signed in as \(user.name) (\(user.country), \(user.plan.lowercased())).")
    }
}

struct Logout: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Forget the stored Deezer ARL.")

    @OptionGroup var options: GlobalOptions

    func run() {
        CredentialStore(paths: options.paths).clear()
        print("Signed out.")
    }
}

struct Config: AsyncParsableCommand {
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
            FileHandle.standardError.write(
                Data(
                    """
                    Unknown bitrate "\(bitrate)". Use one of:
                      flac | lossless | 9
                      mp3_320 | mp3 | 320 | 3
                      mp3_128 | 128 | 1
                      360_hq | mp4_ra3 | 15
                      360_mq | mp4_ra2 | 14
                      360_lq | mp4_ra1 | 13\n
                    """.utf8))
            throw ExitCode.failure
        }
    }

    func run() async throws {
        let (session, _) = try await options.signIn(arl: arl)
        var settings = SettingsStore(paths: options.paths).load()
        if let path { settings.downloadLocation = URL(fileURLWithPath: path).standardizedFileURL.path }
        if let concurrency { settings.queueConcurrency = concurrency }

        let format = bitrate.flatMap(TrackFormat.parse)
        let engine = DownloadEngine(session: session, settings: settings)

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
                FileHandle.standardError.write(Data("Skipping \(link): \(error.localizedDescription)\n".utf8))
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
