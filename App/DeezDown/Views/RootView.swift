import DeezDownKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    @State private var section: SidebarSection? = .home
    @State private var path = NavigationPath()
    @State private var searchText = ""
    @State private var searchTab = SearchTab.all
    @State private var showAddLink = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        Group {
            if model.isRestoring {
                LoadingScreen()
            } else if !model.isSignedIn {
                SignInScreen()
            } else {
                browser
            }
        }
        .background(Color.canvas)
        .tint(.brand)
        .overlay(alignment: .bottom) { ToastView(toast: model.toast) }
        .onReceive(NotificationCenter.default.publisher(for: .showAddLink)) { _ in
            showAddLink = model.isSignedIn
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            guard model.isSignedIn else { return }
            section = .search
            path = NavigationPath()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDownloads)) { _ in
            guard model.isSignedIn else { return }
            section = .downloads
            path = NavigationPath()
        }
        .sheet(isPresented: $showAddLink) { AddLinkSheet() }
    }

    private var browser: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(section: $section, path: $path)
                .navigationSplitViewColumnWidth(min: 196, ideal: 216, max: 280)
        } detail: {
            NavigationStack(path: $path) {
                content
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .album(let id): AlbumScreen(id: id)
                        case .artist(let id): ArtistScreen(id: id)
                        case .playlist(let id): PlaylistScreen(id: id)
                        }
                    }
            }
        }
        .toolbar { toolbar }
    }

    @ViewBuilder
    private var content: some View {
        switch section ?? .home {
        case .home: HomeScreen()
        case .search: SearchScreen(query: $searchText, tab: $searchTab)
        case .favorites: FavoritesScreen()
        case .charts: ChartsScreen()
        case .downloads: DownloadsScreen()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showAddLink = true
            } label: {
                Label("Add Link", systemImage: "plus")
            }
            .help("Add a Deezer link to the queue (⌘L)")
        }
    }
}

struct LoadingScreen: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Signing in…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
