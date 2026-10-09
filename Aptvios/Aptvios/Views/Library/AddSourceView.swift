import SwiftUI
import UniformTypeIdentifiers

struct AddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryViewModel

    var prefillURL: String? = nil

    @State private var kind: SourceKind = .m3u
    @State private var name = ""
    @State private var url = ""
    @State private var pasteText = ""
    @State private var format: PlaylistFormat = .auto
    @State private var inputMode: PlaylistInput = .url
    @State private var showImporter = false

    // Xtream / Stalker
    @State private var username = ""
    @State private var password = ""
    @State private var output = "m3u8"
    @State private var mac = ""

    // Single
    @State private var channelName = ""
    @State private var channelURL = ""
    @State private var channelGroup = "Manuel"
    @State private var channelLogo = ""

    private enum PlaylistInput: String, CaseIterable, Identifiable {
        case url = "URL"
        case paste = "Yapıştır"
        case file = "Dosya"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kaynak tipi", selection: $kind) {
                        ForEach(SourceKind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Kaynak adı (opsiyonel)", text: $name)
                }

                switch kind {
                case .m3u, .txt:
                    playlistSections
                case .xtream:
                    xtreamSections
                case .stalker:
                    stalkerSections
                case .single, .blank:
                    singleSections
                }
            }
            .navigationTitle("Kaynak Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if library.isBusy {
                        ProgressView()
                    } else {
                        Button("Ekle") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.plainText, .data, .item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let fileURL = urls.first else { return }
                    let accessed = fileURL.startAccessingSecurityScopedResource()
                    defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
                    if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                        pasteText = text
                        if name.isEmpty { name = fileURL.deletingPathExtension().lastPathComponent }
                        inputMode = .paste
                        kind = .m3u
                    } else {
                        library.errorMessage = "Dosya okunamadı"
                    }
                case .failure(let error):
                    library.errorMessage = error.localizedDescription
                }
            }
            .onAppear {
                if let prefillURL {
                    url = prefillURL
                    kind = .m3u
                    inputMode = .url
                }
            }
            .alert("Hata", isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(library.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var playlistSections: some View {
        Section {
            Picker("Giriş", selection: $inputMode) {
                ForEach(PlaylistInput.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Format", selection: $format) {
                ForEach(PlaylistFormat.allCases) { Text($0.title).tag($0) }
            }
        }

        if inputMode == .url {
            Section("Playlist URL") {
                TextField("https://…/playlist.m3u", text: $url)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
            }
        } else if inputMode == .paste {
            Section("M3U / TXT içeriği") {
                TextEditor(text: $pasteText)
                    .frame(minHeight: 160)
                    .font(.system(.footnote, design: .monospaced))
            }
        } else {
            Section("Yerel dosya") {
                Button("M3U / TXT seç") { showImporter = true }
                if !pasteText.isEmpty {
                    Text("\(pasteText.split(whereSeparator: \.isNewline).count) satır yüklendi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var xtreamSections: some View {
        Section("Xtream Codes") {
            TextField("Sunucu (http://ip:port)", text: $url)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            TextField("Kullanıcı adı", text: $username)
                .textInputAutocapitalization(.never)
            SecureField("Şifre", text: $password)
            Picker("Çıktı", selection: $output) {
                Text("m3u8").tag("m3u8")
                Text("ts").tag("ts")
            }
        }
    }

    @ViewBuilder
    private var stalkerSections: some View {
        Section("Stalker Portal") {
            TextField("Portal URL", text: $url)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            TextField("MAC (opsiyonel)", text: $mac)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text("MAG uyumlu portal. MAC sunucuda tanımlı olmalı.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var singleSections: some View {
        Section("Tek kanal") {
            TextField("Kanal adı", text: $channelName)
            TextField("Yayın URL", text: $channelURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            TextField("Grup", text: $channelGroup)
            TextField("Logo URL (opsiyonel)", text: $channelLogo)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }
    }

    private var canSave: Bool {
        switch kind {
        case .m3u, .txt:
            if inputMode == .url {
                return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .xtream:
            return !url.isEmpty && !username.isEmpty && !password.isEmpty
        case .stalker:
            return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .single, .blank:
            return !channelURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func save() async {
        switch kind {
        case .m3u, .txt:
            let resolvedFormat: PlaylistFormat = kind == .txt ? .txt : format
            await library.addPlaylistSource(
                name: name,
                url: inputMode == .url ? url : nil,
                pasteText: inputMode != .url ? pasteText : nil,
                format: resolvedFormat
            )
        case .xtream:
            await library.addXtreamSource(
                name: name,
                server: url,
                username: username,
                password: password,
                output: output
            )
        case .stalker:
            await library.addStalkerSource(
                name: name,
                portal: url,
                mac: mac.isEmpty ? nil : mac
            )
        case .single, .blank:
            library.addSingleChannel(
                name: channelName,
                url: channelURL,
                group: channelGroup,
                logo: channelLogo.isEmpty ? nil : channelLogo
            )
        }

        if library.errorMessage == nil {
            dismiss()
        }
    }
}
