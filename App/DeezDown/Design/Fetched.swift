import DeezDownKit
import SwiftUI

/// Every screen built from one fetch loads the same way: reuse what was fetched recently, show
/// a spinner only when there is nothing on screen yet, and turn a failure into a message.
struct Fetched<Value, Content: View>: View {
    private enum Phase {
        case loading
        case loaded(Value)
        case failed(String)
    }

    @Environment(AppModel.self) private var model
    var key: String
    var refreshable = false
    var fetch: (DeezerLibrary) async throws -> Value
    @ViewBuilder var content: (Value) -> Content

    @State private var phase = Phase.loading

    init(
        _ key: String,
        refreshable: Bool = false,
        fetch: @escaping (DeezerLibrary) async throws -> Value,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.key = key
        self.refreshable = refreshable
        self.fetch = fetch
        self.content = content
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 80)
                    .blendsWithToolbar()
            case .loaded(let value):
                content(value)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't Load", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
                .blendsWithToolbar()
            }
        }
        .toolbar {
            if refreshable {
                ToolbarItem {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await load(refresh: true) } }
                        .help("Fetch the latest from Deezer")
                }
            }
        }
        .task(id: key) { await load() }
    }

    /// A refresh skips the cache and keeps the page up until the new one arrives.
    private func load(refresh: Bool = false) async {
        if !refresh {
            if let cached = model.cache.value(key, as: Value.self) {
                phase = .loaded(cached)
                return
            }
            phase = .loading
        }
        do {
            let fresh = try await fetch(model.library)
            model.cache.store(fresh, for: key)
            phase = .loaded(fresh)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
