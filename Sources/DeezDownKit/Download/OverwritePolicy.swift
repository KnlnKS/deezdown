import Foundation

enum OverwriteDecision: Equatable {
    case download(URL)
    case skip(URL)
    case tagOnly(URL)
}

enum OverwritePolicy {
    static let audioExtensions = ["mp3", "flac", "opus", "m4a", "mp4"]

    static func decide(
        base: URL,
        format: TrackFormat,
        duration: Int,
        mode: OverwriteMode,
        manager: FileManager = .default
    ) -> OverwriteDecision {
        let target = base.appendingPathExtension(format.fileExtension)

        switch mode {
        case .overwrite:
            return .download(target)

        case .skipAnyExtension:
            for candidate in audioExtensions.map({ base.appendingPathExtension($0) })
            where manager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return .skip(candidate)
            }
            return .download(target)

        case .skip:
            return manager.fileExists(atPath: target.path(percentEncoded: false))
                ? .skip(target) : .download(target)

        case .tagsOnly:
            return manager.fileExists(atPath: target.path(percentEncoded: false))
                ? .tagOnly(target) : .download(target)

        case .keepBoth:
            guard manager.fileExists(atPath: target.path(percentEncoded: false)) else { return .download(target) }
            var index = 1
            while index < 1000 {
                let candidate = base.deletingLastPathComponent()
                    .appending(path: "\(base.lastPathComponent) (\(index))")
                    .appendingPathExtension(format.fileExtension)
                if !manager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                    return .download(candidate)
                }
                index += 1
            }
            return .download(target)

        case .upgradeBitrate:
            guard manager.fileExists(atPath: target.path(percentEncoded: false)) else { return .download(target) }
            guard format == .mp3_320, duration > 0,
                let size = try? manager.attributesOfItem(atPath: target.path(percentEncoded: false))[.size]
                    as? Int
            else { return .skip(target) }
            let kbps = Double(size) * 8 / 1000 / Double(duration)
            return kbps < 310 ? .download(target) : .skip(target)
        }
    }
}
