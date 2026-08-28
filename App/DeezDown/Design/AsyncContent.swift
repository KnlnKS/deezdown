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
    var items: [Item]
    var minimum: CGFloat = 156
    @ViewBuilder var card: (Item) -> Card

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimum, maximum: minimum * 1.4), spacing: 18, alignment: .top)],
            alignment: .leading,
            spacing: 20
        ) {
            ForEach(items) { item in card(item) }
        }
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
