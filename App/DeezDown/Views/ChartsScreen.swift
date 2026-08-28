import DeezDownKit
import SwiftUI

struct ChartsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<[PlaylistSummary]> = .loading

    var body: some View {
        AsyncContent(state: state, retry: { Task { await load() } }) { countries in
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
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await model.library.chartCountries())
        } catch {
            state = .failed(model.message(for: error))
        }
    }
}
