import ArgumentParser
import DeezDownKit
import Foundation

@main
struct Deezdown: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deezdown",
        abstract: "Download music from Deezer.",
        version: DeezDown.version,
        subcommands: [Download.self, Search.self, Login.self, Config.self],
        defaultSubcommand: Download.self
    )
}

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Keep configuration in ./config instead of Application Support.")
    var portable = false

    var paths: AppPaths { AppPaths(portable: portable) }
}

extension AppPaths {
    static func signIn(_ options: GlobalOptions, arl explicit: String?) async throws -> DeezerSession {
        let credentials = CredentialStore(paths: options.paths)
        let session = DeezerSession()

        if let explicit {
            try await session.login(arl: explicit)
            try credentials.save(arl: explicit)
            return session
        }
        if let stored = credentials.arl(), (try? await session.login(arl: stored)) != nil {
            return session
        }
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
        try await session.login(arl: typed)
        try credentials.save(arl: typed)
        return session
    }
}

struct Login: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Store a Deezer ARL for future runs.")

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "The ARL cookie value. Omit to be prompted.")
    var arl: String?

    func run() async throws {
        let session = try await AppPaths.signIn(options, arl: arl)
        guard let user = await session.user else { throw ExitCode.failure }
        let plan = user.canStreamLossless ? "lossless" : (user.canStreamHQ ? "high quality" : "standard")
        print("Signed in as \(user.name) (\(user.country), \(plan)).")
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
            var configuration = try ConfigurationValue(store.load())
            let settings = try configuration.setting(key, to: value)
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

    @Argument(help: "One or more Deezer links.")
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
        let session = try await AppPaths.signIn(options, arl: arl)
        var settings = SettingsStore(paths: options.paths).load()
        if let path { settings.downloadLocation = URL(fileURLWithPath: path).standardizedFileURL.path }
        if let concurrency { settings.queueConcurrency = concurrency }
        settings.repair()

        let format = bitrate.flatMap(TrackFormat.parse)
        let engine = DownloadEngine(session: session, settings: settings, paths: options.paths)

        var parsed: [DeezerLink] = []
        for link in links.flatMap(LinkParser.split) {
            do {
                parsed.append(try await LinkParser.resolve(link))
            } catch {
                FileHandle.standardError.write(Data("Skipping \(link): \(reason(error))\n".utf8))
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

    private func reason(_ error: any Error) -> String {
        switch error {
        case let failure as DownloadFailure: failure.message
        case LinkParseError.notRecognized: "not a Deezer link"
        case LinkParseError.notSupported: "that kind of Deezer link isn't supported"
        case LinkParseError.invalidID(let id): "\"\(id)\" is not a valid id"
        default: error.localizedDescription
        }
    }
}
