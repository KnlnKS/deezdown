import DeezDownKit
import SwiftUI

struct ChartsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<[PlaylistSummary]> = .loading

    var body: some View {
        AsyncContent(state: state, retry: { Task { await load(force: true) } }) { countries in
            ScreenScroll {
                SectionHeader("Charts", subtitle: "Deezer's top 100 for every country")
                CardGrid(items: countries) { country in
                    NavigationLink(value: Route.playlist(country.id)) {
                        MediaCard(
                            picture: country.picture,
                            title: country.title.replacingOccurrences(of: "Top ", with: ""),
                            subtitle: "\(country.trackCount) tracks",
                            link: country.link
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Charts")
        .toolbar {
            ToolbarItem {
                Button { Task { await load(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Fetch the latest from Deezer")
            }
        }
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        if !force, let cached = model.cache.value("charts", as: [PlaylistSummary].self) {
            state = .loaded(cached)
            return
        }
        if case .loaded = state {} else { state = .loading }
        do {
            let fresh = try await model.library.chartCountries()
            model.cache.store(fresh, for: "charts")
            state = .loaded(fresh)
        } catch {
            state = .failed(model.message(for: error))
        }
    }
}
