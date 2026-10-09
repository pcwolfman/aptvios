import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var library: LibraryViewModel
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            LibraryView()
                .tabItem { Label("Kaynaklar", systemImage: "square.stack.3d.up") }
                .tag(0)

            ChannelBrowserView()
                .tabItem { Label("Kanallar", systemImage: "tv") }
                .tag(1)

            FavoritesView()
                .tabItem { Label("Favoriler", systemImage: "star.fill") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Ayarlar", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(Color.accentColor)
        .sheet(item: Binding(
            get: { library.pendingImportURL.map { ImportURLItem(url: $0) } },
            set: { library.pendingImportURL = $0?.url }
        )) { item in
            AddSourceView(prefillURL: item.url)
        }
    }
}

private struct ImportURLItem: Identifiable {
    let url: String
    var id: String { url }
}
