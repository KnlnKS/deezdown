import Foundation

public enum TrackFormat: Int, Sendable, CaseIterable, Codable, Comparable {
    case local = 0
    case mp3_128 = 1
    case mp3_320 = 3
    case `default` = 8
    case flac = 9
    case mp4ra1 = 13
    case mp4ra2 = 14
    case mp4ra3 = 15

    public static func < (lhs: TrackFormat, rhs: TrackFormat) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var apiName: String {
        switch self {
        case .flac: "FLAC"
        case .mp3_320: "MP3_320"
        case .mp3_128: "MP3_128"
        case .mp4ra3: "MP4_RA3"
        case .mp4ra2: "MP4_RA2"
        case .mp4ra1: "MP4_RA1"
        case .default, .local: "MP3_MISC"
        }
    }

    public var fileExtension: String {
        switch self {
        case .flac: "flac"
        case .mp4ra1, .mp4ra2, .mp4ra3: "mp4"
        default: "mp3"
        }
    }

    public var filesizeKey: String {
        switch self {
        case .flac: "FILESIZE_FLAC"
        case .mp3_320: "FILESIZE_MP3_320"
        case .mp3_128: "FILESIZE_MP3_128"
        case .mp4ra3: "FILESIZE_MP4_RA3"
        case .mp4ra2: "FILESIZE_MP4_RA2"
        case .mp4ra1: "FILESIZE_MP4_RA1"
        case .default, .local: "FILESIZE_MP3_MISC"
        }
    }

    public var displayName: String {
        switch self {
        case .flac: "FLAC"
        case .mp3_320: "320"
        case .mp3_128: "128"
        case .mp4ra3: "360 HQ"
        case .mp4ra2: "360 MQ"
        case .mp4ra1: "360 LQ"
        case .default, .local: "MP3"
        }
    }

    public var isSpatial: Bool {
        self == .mp4ra1 || self == .mp4ra2 || self == .mp4ra3
    }

    public var requiresLossless: Bool {
        self == .flac || isSpatial
    }

    public static let selectable: [TrackFormat] = [.flac, .mp3_320, .mp3_128, .mp4ra3, .mp4ra2, .mp4ra1]

    public static func parse(_ text: String) -> TrackFormat? {
        switch text.lowercased() {
        case "flac", "lossless", "9": .flac
        case "mp3_320", "mp3", "320", "3": .mp3_320
        case "mp3_128", "128", "1": .mp3_128
        case "mp4_ra3", "360", "360_hq", "15": .mp4ra3
        case "mp4_ra2", "360_mq", "14": .mp4ra2
        case "mp4_ra1", "360_lq", "13": .mp4ra1
        default: nil
        }
    }
}
