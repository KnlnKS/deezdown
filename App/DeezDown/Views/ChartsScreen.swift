import DeezDownKit
import SwiftUI

struct ChartsScreen: View {
    var body: some View {
        Fetched("charts", refreshable: true) { try await $0.chartCountries() } content: { countries in
            ScreenScroll {
                SectionHeader("Charts", subtitle: "Deezer's top 100 for every country")
                CardGrid(items: countries) { country in
                    MediaCard(country, title: country.title.replacing("Top ", with: ""))
                }
            }
        }
    }
}
