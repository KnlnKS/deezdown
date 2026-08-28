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

struct CardGrid<Item: Identifiable, Card: View>: View {
    static var maximumColumns: Int { 6 }

    var items: [Item]
    var minimum: CGFloat = 150
    @ViewBuilder var card: (Item) -> Card

    @State private var available: CGFloat = 0

    private var columns: Int {
        guard available > 0 else { return 4 }
        let spacing: CGFloat = 18
        let fits = Int((available + spacing) / (minimum + spacing))
        return max(1, min(Self.maximumColumns, fits))
    }

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(maximum: 210), spacing: 18, alignment: .top),
                count: columns
            ),
            alignment: .leading,
            spacing: 22
        ) {
            ForEach(items) { item in card(item) }
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
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
