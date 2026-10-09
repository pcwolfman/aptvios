import SwiftUI

struct ChannelBrowserView: View {
    @StateObject private var browser = ChannelBrowserViewModel()
    @EnvironmentObject private var playerRouter: PlayerRouter
    @EnvironmentObject private var persistence: PersistenceController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var epg: EPGService
    @State private var showGroups = false
    @State private var detailChannel: PlayableChannel?
    @State private var editChannel: PlayableChannel?
    @State private var showSplit = false

    var body: some View {
        NavigationStack {
            Group {
                if browser.allChannels.isEmpty {
                    ContentUnavailableView(
                        "Kanal yok",
                        systemImage: "tv.slash",
                        description: Text("Önce Kaynaklar sekmesinden bir M3U/TXT listesi ekleyin.")
                    )
                } else {
                    channelList
                }
            }
            .navigationTitle(browser.selectedGroup ?? "Kanallar")
            .searchable(text: $browser.searchText, prompt: "Kanal ara")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showGroups = true
                    } label: {
                        Label("Gruplar", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showSplit = true } label: {
                            Image(systemName: "rectangle.split.2x1")
                        }
                        Text("\(browser.filteredChannels.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showGroups) {
                NavigationStack {
                    List {
                        Button {
                            browser.selectedGroup = nil
                            showGroups = false
                        } label: {
                            HStack {
                                Text("Tümü")
                                Spacer()
                                Text("\(browser.allChannels.count)")
                                    .foregroundStyle(.secondary)
                                if browser.selectedGroup == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        ForEach(browser.groups, id: \.self) { group in
                            Button {
                                browser.selectedGroup = group
                                showGroups = false
                            } label: {
                                HStack {
                                    Text(group)
                                    Spacer()
                                    Text("\(browser.groupCount(group))")
                                        .foregroundStyle(.secondary)
                                    if browser.selectedGroup == group {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Kategoriler")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Kapat") { showGroups = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear { browser.reload() }
            .onReceive(persistence.objectWillChange) { _ in
                browser.reload()
            }
        }
    }

    private var channelList: some View {
        List {
            ForEach(browser.filteredChannels) { channel in
                ChannelRow(
                    channel: channel,
                    showLogo: settings.showChannelLogos,
                    nowTitle: epg.nowAndNext(for: channel.tvgId).now?.title,
                    isFavorite: persistence.isFavorite(url: channel.url),
                    onFavorite: { persistence.toggleFavorite(channel) },
                    onPlay: { play(channel) }
                )
                .swipeActions(edge: .leading) {
                    Button {
                        detailChannel = channel
                    } label: {
                        Label("Detay", systemImage: "info.circle")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button { play(channel) } label: {
                        Label("Oynat", systemImage: "play.fill")
                    }
                    Button { detailChannel = channel } label: {
                        Label("Detay / EPG", systemImage: "list.bullet.rectangle")
                    }
                    Button { editChannel = channel } label: {
                        Label("Düzenle", systemImage: "pencil")
                    }
                    if settings.externalPlayer != .system {
                        Button {
                            _ = settings.externalPlayer.open(streamURL: channel.url)
                        } label: {
                            Label("\(settings.externalPlayer.title) ile aç", systemImage: "arrow.up.forward.app")
                        }
                    }
                    Button {
                        persistence.toggleFavorite(channel)
                    } label: {
                        Label(
                            persistence.isFavorite(url: channel.url) ? "Favorilerden çıkar" : "Favorilere ekle",
                            systemImage: "star"
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .sheet(item: $detailChannel) { channel in
            ChannelDetailView(channel: channel)
        }
        .sheet(item: $editChannel) { channel in
            ChannelEditView(channel: channel)
        }
        .fullScreenCover(isPresented: $showSplit) {
            SplitScreenPlayerView()
        }
    }

    private func play(_ channel: PlayableChannel) {
        if settings.rememberLastChannel {
            settings.lastChannelURL = channel.url
        }
        persistence.recordPlay(channel)
        playerRouter.play(channel, in: browser.filteredChannels)
    }
}
