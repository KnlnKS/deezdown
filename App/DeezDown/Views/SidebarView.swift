import DeezDownKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var section: SidebarSection?
    @Binding var path: NavigationPath

    var body: some View {
        List(selection: $section) {
            Section {
                ForEach(SidebarSection.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: section) { _, _ in path = NavigationPath() }
        .safeAreaInset(edge: .bottom) { account }
    }

    private var account: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                CircularArtworkView(
                    picture: Artwork(md5: model.user?.pictureMD5 ?? "", kind: .user), side: 28
                )
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
        let plan = user.canStreamLossless ? "Lossless" : (user.canStreamHQ ? "High Quality" : "Standard")
        return "\(plan) · \(user.country)"
    }
}
