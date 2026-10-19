import DeezDownKit
import SwiftUI

enum SidebarSection: String {
    case home, favorites, charts, downloads
    /// Not listed in the sidebar: typing in the toolbar's search field leads here.
    case search
}

/// Owns what the detail column shows, so the sidebar, the search field and a context menu
/// (which can't hold a NavigationLink) all move it the same way.
@Observable
final class Navigator {
    private(set) var section: SidebarSection? = .home
    private(set) var query = ""
    var path = NavigationPath()

    func show(_ section: SidebarSection?) {
        self.section = section
        query = ""
        path = NavigationPath()
    }

    /// Typing from anywhere, even a page opened from the results, shows the results.
    func search(_ text: String) {
        query = text
        guard !text.isEmpty else { return }
        // Only real changes, so a keystroke redraws the results rather than the whole window.
        if section != .search { section = .search }
        if !path.isEmpty { path = NavigationPath() }
    }

    func open(_ route: Route) { path.append(route) }
}

extension EnvironmentValues {
    /// What the screen underneath is already showing.
    @Entry var currentRoute: Route?
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
