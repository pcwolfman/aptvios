import SwiftUI

struct SubtitleSearchView: View {
    let queryHint: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    @State private var query = ""
    @State private var results: [SubtitleResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var source = SubSource.openSubtitles

    private enum SubSource: String, CaseIterable, Identifiable {
        case openSubtitles = "OpenSubtitles"
        case assrt = "assrt"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kaynak", selection: $source) {
                        ForEach(SubSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Arama", text: $query)
                    Button("Ara") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }

                if isLoading {
                    ProgressView()
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }

                Section("Sonuçlar") {
                    ForEach(results) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text("\(item.language) · \(item.source)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let link = item.downloadURL, let url = URL(string: link), link.hasPrefix("http") {
                                Link("İndir / aç", destination: url)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Altyazı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .onAppear {
                if query.isEmpty { query = queryHint }
            }
        }
    }

    private func search() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch source {
            case .openSubtitles:
                results = try await SubtitleService.shared.searchOpenSubtitles(
                    query: query,
                    apiKey: settings.openSubtitlesAPIKey
                )
            case .assrt:
                results = try await SubtitleService.shared.searchAssrt(
                    query: query,
                    token: settings.assrtToken.isEmpty ? nil : settings.assrtToken
                )
            }
            if results.isEmpty {
                errorMessage = "Sonuç yok"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
