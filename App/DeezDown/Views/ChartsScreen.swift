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
                    MediaCard(country, title: country.title.replacing("Top ", with: ""))
                }
            }
        }
        .navigationTitle("Charts")
        .toolbar {
            ToolbarItem {
                RefreshButton { Task { await load(force: true) } }
            }
        }
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        await model.load("charts", force: force, into: { state = $0 }) {
            try await model.library.chartCountries()
        }
    }
}
