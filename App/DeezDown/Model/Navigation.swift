import DeezDownKit
import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    static let browsing: [SidebarSection] = [.home, .search, .favorites, .charts]

    case home, search, favorites, charts, downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .favorites: "Favorites"
        case .charts: "Charts"
        case .downloads: "Downloads"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .search: "magnifyingglass"
        case .favorites: "heart"
        case .charts: "chart.bar"
        case .downloads: "arrow.down.circle"
        }
    }
}

enum Route: Hashable {
    case album(String)
    case artist(String)
    case playlist(String)

    init?(link: DeezerLink) {
        switch link {
        case .album(let id): self = .album(id)
        case .artist(let id, _): self = .artist(id)
        case .playlist(let id): self = .playlist(id)
        case .track, .artistTop: return nil
        }
    }
}
