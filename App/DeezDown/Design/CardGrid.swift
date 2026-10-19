import SwiftUI

/// How many cards fit across a given width. Columns are unbounded in width so a grid always
/// spans its container — a fixed card width would leave a widening gutter on the trailing
/// edge — but their number is capped, so a wide window makes the artwork bigger rather than
/// the rows longer.
enum CardColumns {
    static let minimumWidth: CGFloat = 180
    static let maximum = 6

    static func fitting(_ width: CGFloat) -> Int {
        guard width > 0 else { return 4 }
        return min(max(2, Int((width + Metrics.cardGap) / (minimumWidth + Metrics.cardGap))), maximum)
    }
}

struct CardGrid<Item: Identifiable, Card: View>: View {
    var items: [Item]
    @ViewBuilder var card: (Item) -> Card

    @State private var available: CGFloat = 0

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Metrics.cardGap, alignment: .top),
                count: CardColumns.fitting(available)
            ),
            alignment: .leading,
            spacing: Metrics.cardGap + 6
        ) {
            ForEach(items) { item in card(item) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
    }
}

/// A titled shelf that shows a fixed number of rows and pages through the rest, the way
/// Deezer's own home page does. Trimming to fit instead would put whatever did not fit out
/// of reach, and narrowing the window would take more of it away.
struct CardShelf<Item: Identifiable, Card: View>: View {
    var title: String
    var items: [Item]
    var rows: Int
    @ViewBuilder var card: (Item) -> Card

    @State private var page = 0
    @State private var available: CGFloat = 0

    init(_ title: String, items: [Item], rows: Int = 1, @ViewBuilder card: @escaping (Item) -> Card) {
        self.title = title
        self.items = items
        self.rows = rows
        self.card = card
    }

    private var pageSize: Int { CardColumns.fitting(available) * rows }
    private var pageCount: Int { max(1, (items.count + pageSize - 1) / pageSize) }

    private var shown: [Item] {
        let start = min(page, pageCount - 1) * pageSize
        return Array(items[start..<min(start + pageSize, items.count)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title) {
                if pageCount > 1 { PageArrows(page: $page, count: pageCount) }
            }
            CardGrid(items: shown) { card($0) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
        // A narrower window fits fewer per page, which can leave the last page behind.
        .onChange(of: pageCount) { _, count in page = min(page, count - 1) }
        .animation(Motion.standard, value: page)
    }
}

/// Deezer pages its home rows with a pair of chevrons; this is the Mac-weight version.
private struct PageArrows: View {
    @Binding var page: Int
    var count: Int

    var body: some View {
        HStack(spacing: 6) {
            arrow("chevron.left", "Show the previous row", to: page - 1, enabled: page > 0)
            arrow("chevron.right", "Show the next row", to: page + 1, enabled: page < count - 1)
        }
    }

    private func arrow(_ symbol: String, _ label: String, to destination: Int, enabled: Bool) -> some View {
        Button { page = destination } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content()
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
