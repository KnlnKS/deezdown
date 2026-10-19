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

/// A titled row that scrolls sideways and settles on whole cards, so none is left cut off at
/// either edge. The chevrons scroll it a row's width at a time for a mouse without a sideways
/// wheel. With nothing to show it shows nothing, title included.
struct CardShelf<Item: Identifiable, Card: View, Accessory: View>: View {
    var title: String
    var items: [Item]
    @ViewBuilder var card: (Item) -> Card
    @ViewBuilder var accessory: () -> Accessory

    @State private var available: CGFloat = 0
    @State private var leading: Item.ID?

    init(
        _ title: String, items: [Item], @ViewBuilder card: @escaping (Item) -> Card,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.items = items
        self.card = card
        self.accessory = accessory
    }

    private var columns: Int { CardColumns.fitting(available) }
    private var first: Int { leading.flatMap { id in items.firstIndex { $0.id == id } } ?? 0 }

    var body: some View {
        if !items.isEmpty { shelf }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title) {
                HStack(spacing: 6) {
                    accessory()
                    if items.count > columns {
                        arrow("chevron.left", "Show the previous cards", by: -1, enabled: first > 0)
                        arrow("chevron.right", "Show the next cards", by: 1, enabled: first + columns < items.count)
                    }
                }
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Metrics.cardGap) {
                    ForEach(items) { item in
                        card(item).containerRelativeFrame(.horizontal, count: columns, spacing: Metrics.cardGap)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.never)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $leading, anchor: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
        }
    }

    private func arrow(_ symbol: String, _ label: String, by direction: Int, enabled: Bool) -> some View {
        Button {
            let target = min(max(0, first + direction * columns), items.count - columns)
            withAnimation(Motion.standard) { leading = items[target].id }
        } label: {
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
