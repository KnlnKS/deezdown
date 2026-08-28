import SwiftUI

enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

struct AsyncContent<Value, Content: View>: View {
    var state: LoadState<Value>
    var retry: () -> Void
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            LoadingState()
        case .loaded(let value):
            content(value)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: retry)
            }
        }
    }
}

/// Columns are uncapped and unbounded in width so the grid always spans its container —
/// a fixed maximum would leave a widening gutter on the trailing edge as the window grows.
struct CardGrid<Item: Identifiable, Card: View>: View {
    var items: [Item]
    var minimum: CGFloat = 180
    /// Trims the tail so a section never ends in a part-filled row.
    var rows: Int?
    @ViewBuilder var card: (Item) -> Card

    @State private var available: CGFloat = 0

    private var columns: Int {
        guard available > 0 else { return 4 }
        return max(2, Int((available + Metrics.cardGap) / (minimum + Metrics.cardGap)))
    }

    private var shown: [Item] {
        guard let rows else { return items }
        return Array(items.prefix(columns * rows))
    }

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Metrics.cardGap, alignment: .top),
                count: columns
            ),
            alignment: .leading,
            spacing: Metrics.cardGap + 6
        ) {
            ForEach(shown) { item in card(item) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
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
