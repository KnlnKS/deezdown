import DeezDownKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator

    var body: some View {
        List(selection: Binding(get: { navigator.section }, set: navigator.show)) {
            Section {
                row(.home, symbol: "house")
                row(.favorites, symbol: "heart")
                row(.charts, symbol: "chart.bar")
            }
            Section {
                row(.downloads, symbol: "arrow.down.circle", badge: model.summary.active)
            }
        }
        .listStyle(.sidebar)
        .tint(.brand)
        .safeAreaInset(edge: .bottom) { account }
    }

    /// The tag goes on last: a modifier after it hides it from the list's selection.
    private func row(_ section: SidebarSection, symbol: String, badge: Int = 0) -> some View {
        Label(section.rawValue.capitalized, systemImage: symbol)
            .badge(badge)
            .tag(section)
    }

    private var account: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                ArtworkView(picture: Artwork(md5: model.user?.pictureMD5 ?? "", kind: .user), side: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.user?.name ?? "Not signed in")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(planDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Menu {
                    SettingsLink { Text("Settings…") }
                    Button("Open Downloads Folder") { model.revealDownloads() }
                    Divider()
                    Button("Sign Out", role: .destructive) { model.signOut() }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(.bar)
    }

    private var planDescription: String {
        guard let user = model.user else { return "—" }
        return "\(user.plan) · \(user.country)"
    }
}
