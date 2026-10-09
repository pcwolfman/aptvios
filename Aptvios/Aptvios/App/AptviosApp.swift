import SwiftUI

@main
struct AptviosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var persistence = PersistenceController.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var library = LibraryViewModel()
    @StateObject private var playerRouter = PlayerRouter()
    @ObservedObject private var epg = EPGService.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(persistence)
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(playerRouter)
                .environmentObject(epg)
                .preferredColorScheme(settings.forceDarkMode ? .dark : nil)
                .task {
                    epg.loadCached()
                }
                .onOpenURL { url in
                    library.handleDeepLink(url)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { playerRouter.activeChannel != nil },
                    set: { if !$0 { playerRouter.dismiss() } }
                )) {
                    if let channel = playerRouter.activeChannel {
                        PlayerScreen(channel: channel)
                            .environmentObject(playerRouter)
                            .environmentObject(settings)
                            .environmentObject(persistence)
                            .environmentObject(epg)
                    }
                }
        }
    }
}
