import Foundation
import CoreData
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var pendingImportURL: String?

    private var persistence: PersistenceController { .shared }
    private var settings: AppSettings { .shared }

    func addPlaylistSource(
        name: String,
        url: String?,
        pasteText: String?,
        format: PlaylistFormat
    ) async {
        isBusy = true
        errorMessage = nil
        successMessage = nil
        defer { isBusy = false }

        do {
            let raw = pasteText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await PlaylistLoader.shared.loadChannels(
                urlString: url?.trimmingCharacters(in: .whitespacesAndNewlines),
                rawContent: (raw?.isEmpty == false) ? raw : nil,
                format: format,
                userAgent: settings.userAgent
            )

            let sourceName = resolvedName(name, fallback: URL(string: url ?? "")?.host ?? "Playlist")
            let kind: SourceKind = format == .txt ? .txt : .m3u

            _ = persistence.createConfig(
                name: sourceName,
                url: url,
                rawContent: url == nil || url?.isEmpty == true ? result.text : nil,
                format: format.rawValue,
                kind: kind,
                channels: result.channels
            )
            successMessage = "\(result.channels.count) kanal eklendi"
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Geriye uyumluluk
    func addSource(
        name: String,
        url: String?,
        pasteText: String?,
        format: PlaylistFormat
    ) async {
        await addPlaylistSource(name: name, url: url, pasteText: pasteText, format: format)
    }

    func addXtreamSource(
        name: String,
        server: String,
        username: String,
        password: String,
        output: String = "m3u8"
    ) async {
        isBusy = true
        errorMessage = nil
        successMessage = nil
        defer { isBusy = false }

        do {
            let client = try XtreamClient(baseURL: server, username: username, password: password)
            _ = try await client.authenticate()
            let ext = XtreamStreamExtension(rawValue: output) ?? .m3u8
            let channels = try await client.fetchParsedChannels(streamExtension: ext)
            let sourceName = resolvedName(name, fallback: URL(string: server)?.host ?? "Xtream")

            _ = persistence.createConfig(
                name: sourceName,
                url: server,
                rawContent: nil,
                format: "xtream",
                kind: .xtream,
                username: username,
                password: password,
                outputFormat: output,
                channels: channels
            )
            successMessage = "Xtream: \(channels.count) kanal"
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addStalkerSource(
        name: String,
        portal: String,
        mac: String?
    ) async {
        isBusy = true
        errorMessage = nil
        successMessage = nil
        defer { isBusy = false }

        do {
            let client = try StalkerClient(portalURL: portal, macAddress: mac)
            let channels = try await client.fetchParsedChannels()
            let sourceName = resolvedName(name, fallback: URL(string: portal)?.host ?? "Stalker")

            _ = persistence.createConfig(
                name: sourceName,
                url: portal,
                rawContent: nil,
                format: "stalker",
                kind: .stalker,
                macAddress: mac,
                channels: channels
            )
            successMessage = "Stalker: \(channels.count) kanal"
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addSingleChannel(name: String, url: String, group: String, logo: String?) {
        errorMessage = nil
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "URL gerekli"
            return
        }
        let channelName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (URL(string: url)?.lastPathComponent ?? "Kanal")
            : name
        persistence.addSingleChannel(
            name: channelName,
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            groupTitle: group.isEmpty ? "Manuel" : group,
            logo: logo
        )
        successMessage = "Kanal eklendi"
        objectWillChange.send()
    }

    func refresh(_ config: SourceConfig) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            switch config.sourceKind {
            case .xtream:
                guard let server = config.url,
                      let user = config.username,
                      let pass = config.password else {
                    throw AptviosError.invalidURL
                }
                let client = try XtreamClient(baseURL: server, username: user, password: pass)
                let ext = XtreamStreamExtension(rawValue: config.outputFormat ?? "m3u8") ?? .m3u8
                let channels = try await client.fetchParsedChannels(streamExtension: ext)
                persistence.replaceChannels(for: config, with: channels)
                persistence.save()
                successMessage = "\(config.name ?? "Xtream") yenilendi (\(channels.count))"

            case .stalker:
                guard let portal = config.url else { throw AptviosError.invalidURL }
                let client = try StalkerClient(portalURL: portal, macAddress: config.macAddress)
                let channels = try await client.fetchParsedChannels()
                persistence.replaceChannels(for: config, with: channels)
                persistence.save()
                successMessage = "\(config.name ?? "Stalker") yenilendi (\(channels.count))"

            case .single, .blank:
                successMessage = "Manuel kaynak — yenileme yok"

            case .m3u, .txt:
                let format = PlaylistFormat(rawValue: config.format ?? "auto") ?? .auto
                let result = try await PlaylistLoader.shared.loadChannels(
                    urlString: config.url,
                    rawContent: config.url == nil || config.url?.isEmpty == true ? config.rawContent : nil,
                    format: format,
                    userAgent: settings.userAgent
                )
                persistence.replaceChannels(for: config, with: result.channels)
                persistence.save()
                successMessage = "\(config.name ?? "Kaynak") yenilendi (\(result.channels.count))"
            }
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAll() async {
        let request = SourceConfig.fetchRequest()
        request.predicate = NSPredicate(format: "isEnabled == YES")
        let configs = (try? persistence.viewContext.fetch(request)) ?? []
        for config in configs {
            let kind = config.sourceKind
            if kind == .blank || kind == .single { continue }
            await refresh(config)
        }
    }

    func merge(_ config: SourceConfig, strategy: ChannelMergeService.Strategy) {
        persistence.mergeChannels(in: config, strategy: strategy)
        successMessage = "Kanallar birleştirildi (\(config.channelCount))"
        objectWillChange.send()
    }

    func toggleEnabled(_ config: SourceConfig) {
        config.isEnabled.toggle()
        persistence.save()
        objectWillChange.send()
    }

    func delete(_ config: SourceConfig) {
        persistence.deleteConfig(config)
        objectWillChange.send()
    }

    func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        if let playlist = items.first(where: { $0.name == "url" })?.value {
            pendingImportURL = playlist.removingPercentEncoding ?? playlist
        } else if url.host == "add" || components.path.contains("add") {
            pendingImportURL = items.first(where: { ["url", "link", "src"].contains($0.name) })?.value
        }
    }

    private func resolvedName(_ name: String, fallback: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }
}
