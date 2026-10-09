import SwiftUI

struct ChannelEditView: View {
    let channel: PlayableChannel

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var persistence: PersistenceController

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var logo: String = ""
    @State private var groupTitle: String = ""
    @State private var tvgId: String = ""
    @State private var userAgent: String = ""
    @State private var referer: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Kanal") {
                    TextField("Ad", text: $name)
                    TextField("URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Grup", text: $groupTitle)
                    TextField("Logo URL", text: $logo)
                        .textInputAutocapitalization(.never)
                    TextField("tvg-id", text: $tvgId)
                        .textInputAutocapitalization(.never)
                }
                Section("HTTP") {
                    TextField("User-Agent", text: $userAgent)
                        .textInputAutocapitalization(.never)
                    TextField("Referer", text: $referer)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Kanalı Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Sil", role: .destructive) {
                        persistence.deleteChannel(id: channel.id)
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = channel.name
                url = channel.url
                logo = channel.logo ?? ""
                groupTitle = channel.groupTitle
                tvgId = channel.tvgId ?? ""
                userAgent = channel.userAgent ?? ""
                referer = channel.referer ?? ""
            }
        }
    }

    private func save() {
        persistence.updateChannel(
            id: channel.id,
            name: name,
            url: url,
            logo: logo.isEmpty ? nil : logo,
            groupTitle: groupTitle.isEmpty ? "Uncategorized" : groupTitle,
            tvgId: tvgId.isEmpty ? nil : tvgId,
            userAgent: userAgent.isEmpty ? nil : userAgent,
            referer: referer.isEmpty ? nil : referer
        )
        dismiss()
    }
}
