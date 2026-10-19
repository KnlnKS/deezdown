import DeezDownKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    @State private var navigator = Navigator()
    @State private var findRequest: UUID?

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
        .overlay(alignment: .bottom) { ToastView() }
        .onChange(of: model.command) { _, command in
            guard let command, model.isSignedIn else { return }
            switch command.kind {
            case .findInSearch: findRequest = command.id
            case .showDownloads: navigator.show(.downloads)
            }
        }
    }

    private var browser: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 196, ideal: 216, max: 280)
        } detail: {
            NavigationStack(path: $navigator.path) {
                page(content)
                    .navigationDestination(for: Route.self) { page(screen(for: $0)) }
            }
        }
        .environment(navigator)
        .toolbar(removing: .title)
        .toolbar {
            // The stack's own back button would land after the search field, so this one
            // stands in for it.
            ToolbarItem(placement: .navigation) {
                Button("Back", systemImage: "chevron.left") { navigator.path.removeLast() }
                    .disabled(navigator.path.isEmpty)
                    .keyboardShortcut("[")
                    .help("Back")
            }
            ToolbarItem(placement: .navigation) {
                SearchField(
                    text: Binding(get: { navigator.query }, set: navigator.search),
                    focusRequest: findRequest,
                    onSubmit: submitSearch
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch navigator.section ?? .home {
        case .home: HomeScreen()
        case .search: SearchScreen()
        case .favorites: FavoritesScreen()
        case .charts: ChartsScreen()
        case .downloads: DownloadsScreen()
        }
    }

    @ViewBuilder
    private func screen(for route: Route) -> some View {
        switch route {
        case .album(let id): AlbumScreen(id: id)
        case .artist(let id): ArtistScreen(id: id)
        case .playlist(let id): PlaylistScreen(id: id)
        }
    }

    /// Every page in the stack carries the spacer that pushes its actions to the trailing edge,
    /// since on the split view a shared one is dropped.
    private func page(_ screen: some View) -> some View {
        screen
            .toolbar { ToolbarSpacer(.flexible) }
            .navigationBarBackButtonHidden()
    }

    private func submitSearch() {
        let text = navigator.query
        guard LinkParser.split(text).contains(where: LinkParser.isLink) else { return }
        Task { await model.enqueue(pasted: text) }
        navigator.search("")
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
