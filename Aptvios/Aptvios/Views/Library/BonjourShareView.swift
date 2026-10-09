import SwiftUI

struct BonjourShareView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryViewModel
    @StateObject private var bonjour = BonjourSyncService.shared

    @State private var shareURL = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Yayınla") {
                    TextField("Paylaşılacak playlist URL", text: $shareURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Toggle("Bonjour ile yayınla", isOn: Binding(
                        get: { bonjour.isAdvertising },
                        set: { on in
                            if on {
                                bonjour.startAdvertising(playlistURL: shareURL)
                            } else {
                                bonjour.stopAdvertising()
                            }
                        }
                    ))
                    .disabled(shareURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Yakındaki cihazlar") {
                    Button(bonjour.discovered.isEmpty ? "Tara" : "Yeniden tara") {
                        bonjour.startBrowsing()
                    }
                    ForEach(bonjour.discovered) { peer in
                        Text(peer.name)
                    }
                    if bonjour.discovered.isEmpty {
                        Text("Henüz cihaz yok").foregroundStyle(.secondary)
                    }
                }

                if let err = bonjour.lastError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("Yerel Paylaşım")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        bonjour.stopAdvertising()
                        bonjour.stopBrowsing()
                        dismiss()
                    }
                }
            }
        }
    }
}
