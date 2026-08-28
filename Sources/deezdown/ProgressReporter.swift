import DeezDownKit
import Foundation

final class ProgressReporter {
    private var lastLines = 0
    private let isTerminal = isatty(FileHandle.standardOutput.fileDescriptor) == 1

    func render(_ queue: [QueueItem]) {
        guard isTerminal else { return }
        var output = ""
        if lastLines > 0 { output += "\u{1B}[\(lastLines)A\u{1B}[0J" }
        let visible = queue.prefix(12)
        for item in visible {
            output += line(for: item) + "\n"
        }
        if queue.count > visible.count {
            output += "  … and \(queue.count - visible.count) more\n"
        }
        lastLines = visible.count + (queue.count > visible.count ? 1 : 0)
        FileHandle.standardOutput.write(Data(output.utf8))
    }

    private func line(for item: QueueItem) -> String {
        let width = 24
        let filled = Int((item.progress * Double(width)).rounded())
        let bar = String(repeating: "━", count: filled) + String(repeating: "─", count: width - filled)
        let counter =
            item.totalTracks > 0 ? "\(item.completedTracks + item.failedTracks)/\(item.totalTracks)" : "—"
        let title = pad("\(item.title) · \(item.subtitle)", to: 44)
        return "  \(symbol(for: item)) \(title) \(bar) \(pad(counter, to: 7)) \(item.status.rawValue)"
    }

    private func symbol(for item: QueueItem) -> String {
        switch item.status {
        case .completed: "✓"
        case .failed: "✗"
        case .withErrors: "!"
        case .canceled: "-"
        default: "•"
        }
    }

    private func pad(_ text: String, to width: Int) -> String {
        let trimmed = text.count > width ? String(text.prefix(width - 1)) + "…" : text
        return trimmed + String(repeating: " ", count: max(0, width - trimmed.count))
    }

    func summarize(_ queue: [QueueItem]) {
        let tracks = queue.reduce(0) { $0 + $1.completedTracks }
        let failed = queue.reduce(0) { $0 + $1.failedTracks }
        var summary = "\nDownloaded \(tracks) track\(tracks == 1 ? "" : "s")"
        if failed > 0 { summary += ", \(failed) failed" }
        if let destination = queue.compactMap(\.destination).first {
            summary += "\n\(destination.path(percentEncoded: false))"
        }
        print(summary)
        for item in queue where !item.issues.isEmpty {
            for issue in item.issues.prefix(10) {
                FileHandle.standardError.write(
                    Data("  ✗ \(issue.artist) - \(issue.title): \(issue.message)\n".utf8))
            }
        }
    }
}
