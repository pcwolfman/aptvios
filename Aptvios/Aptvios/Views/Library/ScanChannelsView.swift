import SwiftUI

struct ScanChannelsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var settings: AppSettings

    @State private var pattern = "http://192.168.1.1:8080/000000001000(0-9)/index.m3u8"
    @State private var groupName = "Tarama"
    @State private var isScanning = false
    @State private var found: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Kalıp URL", text: $pattern)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())

                    TextField("Grup adı", text: $groupName)
                } header: {
                    Text("Kanal tarama")
                } footer: {
                    Text("(0-9) onluk, (0-f) onaltılık yer tutucu. Çalışan URL’ler yeni kaynak olarak eklenir.")
                }

                if !found.isEmpty {
                    Section("Bulunan (\(found.count))") {
                        ForEach(found, id: \.self) { url in
                            Text(url)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await scan() }
                    } label: {
                        if isScanning {
                            ProgressView()
                        } else {
                            Label("Tara", systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                    .disabled(isScanning || pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !found.isEmpty {
                        Button("Kaynak olarak ekle") {
                            Task { await importFound() }
                        }
                        .disabled(isScanning)
                    }
                }
            }
            .navigationTitle("Tarama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .alert("Hata", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func scan() async {
        isScanning = true
        errorMessage = nil
        found = []
        defer { isScanning = false }

        let results = await URLScanner.probe(
            pattern: pattern.trimmingCharacters(in: .whitespacesAndNewlines),
            userAgent: settings.userAgent
        )
        found = results
        if results.isEmpty {
            errorMessage = "Çalışan yayın bulunamadı"
        }
    }

    private func importFound() async {
        let group = groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Tarama"
            : groupName.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines = ["#EXTM3U"]
        for (index, url) in found.enumerated() {
            lines.append("#EXTINF:-1 group-title=\"\(group)\",\(group) \(index + 1)")
            lines.append(url)
        }

        await library.addSource(
            name: group,
            url: nil,
            pasteText: lines.joined(separator: "\n"),
            format: .m3u
        )

        if library.errorMessage == nil {
            dismiss()
        } else {
            errorMessage = library.errorMessage
        }
    }
}
