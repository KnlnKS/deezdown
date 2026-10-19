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
        mode: OverwriteMode
    ) -> OverwriteDecision {
        let manager = FileManager.default
        func exists(_ url: URL) -> Bool { manager.fileExists(atPath: url.path(percentEncoded: false)) }
        let target = base.appendingPathExtension(format.fileExtension)

        switch mode {
        case .overwrite:
            return .download(target)

        case .skipAnyExtension:
            for candidate in audioExtensions.map({ base.appendingPathExtension($0) }) where exists(candidate) {
                return .skip(candidate)
            }
            return .download(target)

        case .skip:
            return exists(target) ? .skip(target) : .download(target)

        case .tagsOnly:
            return exists(target) ? .tagOnly(target) : .download(target)

        case .keepBoth:
            guard exists(target) else { return .download(target) }
            for index in 1..<1000 {
                let candidate = base.deletingLastPathComponent()
                    .appending(path: "\(base.lastPathComponent) (\(index))")
                    .appendingPathExtension(format.fileExtension)
                if !exists(candidate) { return .download(candidate) }
            }
            return .download(target)

        case .upgradeBitrate:
            guard exists(target) else { return .download(target) }
            guard format == .mp3_320, duration > 0,
                let size = try? manager.attributesOfItem(atPath: target.path(percentEncoded: false))[.size]
                    as? Int
            else { return .skip(target) }
            let kbps = Double(size) * 8 / 1000 / Double(duration)
            return kbps < 310 ? .download(target) : .skip(target)
        }
    }
}
