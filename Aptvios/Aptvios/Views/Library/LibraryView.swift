import SwiftUI
import CoreData

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var persistence: PersistenceController
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SourceConfig.createdAt, ascending: false)],
        animation: .default
    )
    private var configs: FetchedResults<SourceConfig>

    @State private var showAdd = false
    @State private var showScan = false
    @State private var showBonjour = false
    @State private var showSplit = false

    var body: some View {
        NavigationStack {
            Group {
                if configs.isEmpty {
                    ContentUnavailableView {
                        Label("Kaynak yok", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("M3U, TXT, Xtream veya Stalker kaynağı ekleyin.")
                    } actions: {
                        Button("Kaynak Ekle") { showAdd = true }
                            .buttonStyle(.borderedProminent)
                        Button("Kanal Tara") { showScan = true }
                    }
                } else {
                    List {
                        Section {
                            ForEach(configs, id: \.objectID) { config in
                                SourceRow(config: config)
                            }
                            .onDelete(perform: delete)
                        }

                        if !persistence.recentChannels().isEmpty {
                            Section("Son izlenenler") {
                                ForEach(persistence.recentChannels()) { channel in
                                    RecentMiniRow(channel: channel)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Kaynaklar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if library.isBusy {
                        ProgressView()
                    } else {
                        Button {
                            Task { await library.refreshAll() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(configs.isEmpty)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAdd = true } label: {
                            Label("Kaynak Ekle", systemImage: "plus")
                        }
                        Button { showScan = true } label: {
                            Label("Kanal Tara", systemImage: "dot.radiowaves.left.and.right")
                        }
                        Button { showBonjour = true } label: {
                            Label("Yerel Paylaşım", systemImage: "wifi")
                        }
                        Button { showSplit = true } label: {
                            Label("Çoklu Ekran", systemImage: "rectangle.split.2x1")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddSourceView() }
            .sheet(isPresented: $showScan) { ScanChannelsView() }
            .sheet(isPresented: $showBonjour) { BonjourShareView() }
            .fullScreenCover(isPresented: $showSplit) { SplitScreenPlayerView() }
            .alert("Hata", isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )) {
                Button("Tamam", role: .cancel) { library.errorMessage = nil }
            } message: {
                Text(library.errorMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if let msg = library.successMessage {
                    Text(msg)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                library.successMessage = nil
                            }
                        }
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            library.delete(configs[index])
        }
    }
}

private struct SourceRow: View {
    @ObservedObject var config: SourceConfig
    @EnvironmentObject private var library: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(config.name ?? "Kaynak").font(.headline)
                        Text(config.sourceKind.title)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    Text("\(config.channelCount) kanal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = config.url, !url.isEmpty {
                        Text(url)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if let refreshed = config.lastRefreshed {
                        Text(refreshed, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { config.isEnabled },
                    set: { _ in library.toggleEnabled(config) }
                ))
                .labelsHidden()
            }

            HStack(spacing: 8) {
                Button {
                    Task { await library.refresh(config) }
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(config.sourceKind == .blank || config.sourceKind == .single)

                Menu("Birleştir") {
                    Button("Ada göre") {
                        library.merge(config, strategy: .byNameAndGroup)
                    }
                    Button("tvg-id’ye göre") {
                        library.merge(config, strategy: .byTvgId)
                    }
                    Button("URL’ye göre") {
                        library.merge(config, strategy: .byURLHostPath)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .opacity(config.isEnabled ? 1 : 0.45)
    }
}

private struct RecentMiniRow: View {
    let channel: PlayableChannel
    @EnvironmentObject private var playerRouter: PlayerRouter
    @EnvironmentObject private var persistence: PersistenceController
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button {
            if settings.rememberLastChannel {
                settings.lastChannelURL = channel.url
            }
            persistence.recordPlay(channel)
            playerRouter.play(channel, in: persistence.recentChannels())
        } label: {
            HStack {
                ChannelLogo(url: channel.logo, size: 36)
                Text(channel.name).foregroundStyle(.primary)
                Spacer()
            }
        }
    }
}
