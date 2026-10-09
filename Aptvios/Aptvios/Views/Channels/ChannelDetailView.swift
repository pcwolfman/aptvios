import SwiftUI

struct ChannelDetailView: View {
    let channel: PlayableChannel

    @EnvironmentObject private var playerRouter: PlayerRouter
    @EnvironmentObject private var persistence: PersistenceController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var epg: EPGService
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var showSubs = false

    private var programs: [EPGProgram] {
        guard let id = channel.tvgId else { return [] }
        return (epg.programsByChannel[id] ?? []).sorted { $0.start < $1.start }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ChannelLogo(url: channel.logo, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(channel.name).font(.title3.bold())
                            Text(channel.groupTitle).foregroundStyle(.secondary)
                            if let source = channel.sourceName {
                                Text(source).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Button {
                        persistence.recordPlay(channel)
                        if settings.rememberLastChannel {
                            settings.lastChannelURL = channel.url
                        }
                        playerRouter.play(channel)
                        dismiss()
                    } label: {
                        Label("Oynat", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        persistence.toggleFavorite(channel)
                    } label: {
                        Label(
                            persistence.isFavorite(url: channel.url) ? "Favorilerden çıkar" : "Favorilere ekle",
                            systemImage: persistence.isFavorite(url: channel.url) ? "star.slash" : "star"
                        )
                    }

                    Button { showEdit = true } label: {
                        Label("Düzenle", systemImage: "pencil")
                    }

                    Button { showSubs = true } label: {
                        Label("Altyazı ara", systemImage: "captions.bubble")
                    }

                    if settings.externalPlayer != .system {
                        Button {
                            _ = settings.externalPlayer.open(streamURL: channel.url)
                        } label: {
                            Label("\(settings.externalPlayer.title) ile aç", systemImage: "arrow.up.forward.app")
                        }
                    }
                }

                Section("Yayın URL") {
                    Text(channel.url)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                if !programs.isEmpty {
                    Section("EPG") {
                        ForEach(programs.prefix(40)) { program in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(program.title).font(.subheadline.weight(.semibold))
                                    if program.isNow {
                                        Text("ŞİMDİ")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.red.opacity(0.85), in: Capsule())
                                            .foregroundStyle(.white)
                                    }
                                }
                                Text("\(program.start.formatted(date: .omitted, time: .shortened)) – \(program.stop.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let desc = program.desc {
                                    Text(desc).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Kanal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(isPresented: $showEdit) {
                ChannelEditView(channel: channel)
            }
            .sheet(isPresented: $showSubs) {
                SubtitleSearchView(queryHint: channel.name)
            }
        }
    }
}
