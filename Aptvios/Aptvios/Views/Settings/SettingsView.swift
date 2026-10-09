import SwiftUI
import CoreData

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var persistence: PersistenceController
    @EnvironmentObject private var epg: EPGService
    @State private var proxyHost = ""
    @State private var proxyPort = "8080"
    @State private var proxyUser = ""
    @State private var proxyPass = ""
    @State private var proxyEnabled = false
    @State private var showSplit = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Oynatıcı") {
                    Picker("Motor", selection: $settings.playerEngine) {
                        ForEach(PlayerEngineKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Dış oynatıcı", selection: $settings.externalPlayer) {
                        ForEach(ExternalPlayer.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Otomatik oynat", isOn: $settings.autoPlay)
                    Toggle("Arka plan sesi", isOn: $settings.backgroundPlayback)
                    Toggle("HomePod senkron modu", isOn: $settings.homePodMode)
                    Toggle("Kanal logoları", isOn: $settings.showChannelLogos)
                    Toggle("Önizleme üret (deneysel)", isOn: $settings.showPreviews)
                    Toggle("Son kanalı hatırla", isOn: $settings.rememberLastChannel)
                    Toggle("Koyu tema", isOn: $settings.forceDarkMode)
                    Button("Çoklu ekran aç") { showSplit = true }
                }

                Section("User-Agent") {
                    TextField("User-Agent", text: $settings.userAgent)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Varsayılana dön") {
                        settings.userAgent = AppSettings.defaultUserAgent
                    }
                }

                Section {
                    Picker("Mod", selection: $settings.epgMode) {
                        ForEach(EPGMode.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("EPG URL / DIYP base", text: $settings.epgURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    Button {
                        Task {
                            await epg.refresh(
                                from: settings.epgURL,
                                mode: settings.epgMode
                            )
                        }
                    } label: {
                        if epg.isLoading { ProgressView() }
                        else { Label("EPG indir / yenile", systemImage: "calendar.badge.clock") }
                    }

                    if let updated = epg.lastUpdated {
                        Text("Son güncelleme: \(updated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let err = epg.lastError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("EPG")
                } footer: {
                    Text("XMLTV (.xml/.gz) veya DIYP JSON API. DIYP için kanalların tvg-id alanları gerekir.")
                }

                Section("Altyazı API") {
                    SecureField("OpenSubtitles API Key", text: $settings.openSubtitlesAPIKey)
                        .textInputAutocapitalization(.never)
                    SecureField("assrt token (opsiyonel)", text: $settings.assrtToken)
                        .textInputAutocapitalization(.never)
                }

                Section("HTTP Proxy") {
                    Toggle("Proxy kullan", isOn: $proxyEnabled)
                    TextField("Host", text: $proxyHost)
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $proxyPort).keyboardType(.numberPad)
                    TextField("Kullanıcı", text: $proxyUser)
                        .textInputAutocapitalization(.never)
                    SecureField("Şifre", text: $proxyPass)
                    Button("Kaydet") { saveProxy() }
                }

                Section {
                    Toggle("iCloud senkron (yeniden başlatma gerekir)", isOn: $settings.iCloudSync)
                    Text(persistence.iCloudEnabled ? "Bu oturumda CloudKit açık" : "Bu oturumda yerel depolama")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Açtıktan sonra uygulamayı kapatıp açın. Xcode’da iCloud capability + container: iCloud.com.aptvios.app")
                }

                Section("Veri") {
                    Button("Son izlenenleri temizle", role: .destructive) { clearRecent() }
                    Button("Önizleme önbelleğini temizle", role: .destructive) {
                        Task { await PreviewThumbnailService.shared.clearCache() }
                    }
                }

                Section("Hakkında") {
                    LabeledContent("Uygulama", value: "Aptvios")
                    LabeledContent("Sürüm", value: "1.2.0")
                    LabeledContent("Motor", value: settings.playerEngine.title)
                    LabeledContent("CarPlay", value: "Favori · Kategori · Ara · EPG · Now Playing")
                    Link("KSPlayer", destination: URL(string: "https://github.com/kingslay/KSPlayer")!)
                }
            }
            .navigationTitle("Ayarlar")
            .onAppear(perform: loadProxy)
            .onAppear { epg.loadCached() }
            .fullScreenCover(isPresented: $showSplit) { SplitScreenPlayerView() }
        }
    }

    private func loadProxy() {
        if let p = persistence.activeProxy() {
            proxyEnabled = p.isEnabled
            proxyHost = p.host ?? ""
            proxyPort = String(p.port)
            proxyUser = p.username ?? ""
            proxyPass = p.password ?? ""
        }
    }

    private func saveProxy() {
        let request = ProxyConfig.fetchRequest()
        let existing = (try? persistence.viewContext.fetch(request)) ?? []
        existing.forEach { persistence.viewContext.delete($0) }

        let proxy = ProxyConfig(context: persistence.viewContext)
        proxy.id = UUID()
        proxy.host = proxyHost
        proxy.port = Int32(proxyPort) ?? 8080
        proxy.username = proxyUser.isEmpty ? nil : proxyUser
        proxy.password = proxyPass.isEmpty ? nil : proxyPass
        proxy.type = "http"
        proxy.isEnabled = proxyEnabled && !proxyHost.isEmpty
        proxy.createdAt = Date()
        persistence.save()
        ProxySession.shared.apply(proxy: proxy.isEnabled ? proxy : nil)
    }

    private func clearRecent() {
        let request = RecentlyPlayed.fetchRequest()
        let items = (try? persistence.viewContext.fetch(request)) ?? []
        items.forEach { persistence.viewContext.delete($0) }
        persistence.save()
    }
}

enum ProxySession {
    static let shared = ProxySessionBox()
}

final class ProxySessionBox {
    private(set) var configuration = URLSessionConfiguration.default

    func apply(proxy: ProxyConfig?) {
        let config = URLSessionConfiguration.default
        if let proxy, proxy.isEnabled, let host = proxy.host, !host.isEmpty {
            var dict: [String: Any] = [
                "HTTPEnable": 1,
                "HTTPProxy": host,
                "HTTPPort": Int(proxy.port),
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": Int(proxy.port)
            ]
            if let user = proxy.username, let pass = proxy.password {
                dict["HTTPUser"] = user
                dict["HTTPPassword"] = pass
            }
            config.connectionProxyDictionary = dict
        }
        configuration = config
    }
}
