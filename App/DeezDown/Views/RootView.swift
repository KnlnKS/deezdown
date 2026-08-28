import DeezDownKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    @State private var section: SidebarSection? = .home
    @State private var path = NavigationPath()
    @State private var searchText = ""
    @State private var showAddLink = false
    @SceneStorage("queueVisible") private var queueVisible = true
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
            .inspector(isPresented: $queueVisible) {
                QueueInspector()
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
            .toolbar { toolbar }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Artists, albums, tracks, or a Deezer link")
        .onSubmit(of: .search) { submitSearch() }
        .onChange(of: searchText) { _, value in
            if !value.isEmpty, section != .search { section = .search }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section ?? .home {
        case .home: HomeScreen()
        case .search: SearchScreen(query: searchText)
        case .favorites: FavoritesScreen()
        case .charts: ChartsScreen()
        case .analyzer: LinkAnalyzerScreen()
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
        ToolbarItem(placement: .primaryAction) {
            Button {
                queueVisible.toggle()
            } label: {
                Label("Queue", systemImage: "arrow.down.circle")
                    .badge(model.activeDownloads)
            }
            .help("Show the download queue")
        }
    }

    private func submitSearch() {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let link = try? LinkParser.parse(text) {
            Task { await model.enqueue(link) }
            searchText = ""
        } else {
            section = .search
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
