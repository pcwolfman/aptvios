import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var persistence: PersistenceController
    @EnvironmentObject private var playerRouter: PlayerRouter
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var epg: EPGService
    @State private var favorites: [PlayableChannel] = []

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    ContentUnavailableView(
                        "Favori yok",
                        systemImage: "star",
                        description: Text("Kanal satırındaki yıldıza dokunarak favorilere ekleyin.")
                    )
                } else {
                    List {
                        ForEach(favorites) { channel in
                            ChannelRow(
                                channel: channel,
                                showLogo: settings.showChannelLogos,
                                nowTitle: epg.nowAndNext(for: channel.tvgId).now?.title,
                                isFavorite: true,
                                onFavorite: {
                                    persistence.toggleFavorite(channel)
                                    reload()
                                },
                                onPlay: {
                                    if settings.rememberLastChannel {
                                        settings.lastChannelURL = channel.url
                                    }
                                    persistence.recordPlay(channel)
                                    playerRouter.play(channel, in: favorites)
                                }
                            )
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                persistence.toggleFavorite(favorites[i])
                            }
                            reload()
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Favoriler")
            .onAppear(perform: reload)
            .onReceive(persistence.objectWillChange) { _ in reload() }
        }
    }

    private func reload() {
        favorites = persistence.favoriteChannels()
    }
}
