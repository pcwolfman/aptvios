import CarPlay
import UIKit

/// APTV seviyesinde CarPlay Audio:
/// Favoriler · Son · Kategoriler · Kanallar · Ara · Now Playing
/// EPG satırı, logo, sonraki/önceki, favori, yenile.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSearchTemplateDelegate {
    private var interfaceController: CPInterfaceController?
    private var favoritesTemplate: CPListTemplate?
    private var recentTemplate: CPListTemplate?
    private var categoriesTemplate: CPListTemplate?
    private var channelsTemplate: CPListTemplate?
    private var searchEntryTemplate: CPListTemplate?

    private let playback = CarPlayPlaybackController.shared
    private let maxListItems = 150
    private var allChannelsCache: [PlayableChannel] = []

    // MARK: - Scene

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        playback.onChannelChanged = { [weak self] _ in
            Task { @MainActor in
                self?.configureNowPlayingButtons()
                self?.reloadLists()
            }
        }

        Task { @MainActor in
            EPGService.shared.loadCached()
            self.refreshCache()
            interfaceController.setRootTemplate(self.makeRootTemplate(), animated: true) { _, _ in }
            self.configureNowPlayingButtons()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        playback.stop()
        self.interfaceController = nil
    }

    // MARK: - Root tabs

    @MainActor
    private func makeRootTemplate() -> CPTabBarTemplate {
        favoritesTemplate = makeList(
            title: "Favoriler",
            image: "star.fill",
            sections: sections(for: PersistenceController.shared.favoriteChannels(), empty: "Favori yok")
        )

        recentTemplate = makeList(
            title: "Son",
            image: "clock.fill",
            sections: sections(for: PersistenceController.shared.recentChannels(), empty: "Henüz izlenen yok")
        )

        categoriesTemplate = makeList(
            title: "Kategoriler",
            image: "square.grid.2x2.fill",
            sections: categorySections()
        )

        channelsTemplate = makeList(
            title: "Kanallar",
            image: "tv",
            sections: groupedSections(Array(allChannelsCache.prefix(maxListItems)))
        )

        searchEntryTemplate = makeSearchEntryTemplate()

        return CPTabBarTemplate(templates: [
            favoritesTemplate!,
            recentTemplate!,
            categoriesTemplate!,
            channelsTemplate!,
            searchEntryTemplate!,
            CPNowPlayingTemplate.shared
        ])
    }

    @MainActor
    private func makeList(title: String, image: String, sections: [CPListSection]) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: sections)
        template.tabTitle = title
        template.tabImage = UIImage(systemName: image)
        return template
    }

    @MainActor
    private func makeSearchEntryTemplate() -> CPListTemplate {
        let open = CPListItem(text: "Kanal ara…", detailText: "İsim, grup veya tvg-id")
        open.setImage(UIImage(systemName: "magnifyingglass"))
        open.handler = { [weak self] _, completion in
            Task { @MainActor in
                let search = CPSearchTemplate()
                search.delegate = self
                self?.interfaceController?.push(template: search, animated: true)
                completion()
            }
        }

        let hint = CPListItem(
            text: "İpucu",
            detailText: "Yazmaya başlayın — sonuçlara dokunarak oynatın"
        )
        hint.setImage(UIImage(systemName: "info.circle"))

        let template = CPListTemplate(title: "Ara", sections: [CPListSection(items: [open, hint])])
        template.tabTitle = "Ara"
        template.tabImage = UIImage(systemName: "magnifyingglass")
        return template
    }

    @MainActor
    private func refreshCache() {
        allChannelsCache = PersistenceController.shared.allEnabledChannels()
    }

    @MainActor
    private func reloadLists() {
        refreshCache()
        favoritesTemplate?.updateSections(
            sections(for: PersistenceController.shared.favoriteChannels(), empty: "Favori yok")
        )
        recentTemplate?.updateSections(
            sections(for: PersistenceController.shared.recentChannels(), empty: "Henüz izlenen yok")
        )
        categoriesTemplate?.updateSections(categorySections())
        channelsTemplate?.updateSections(groupedSections(Array(allChannelsCache.prefix(maxListItems))))
    }

    // MARK: - List builders

    @MainActor
    private func sections(for channels: [PlayableChannel], empty: String) -> [CPListSection] {
        if channels.isEmpty {
            return [CPListSection(items: [
                CPListItem(text: empty, detailText: "Telefonda kaynak / favori ekleyin")
            ])]
        }
        let items = channels.prefix(maxListItems).map { listItem(for: $0, queue: channels) }
        return [CPListSection(items: Array(items))]
    }

    @MainActor
    private func groupedSections(_ channels: [PlayableChannel]) -> [CPListSection] {
        if channels.isEmpty {
            return [CPListSection(items: [
                CPListItem(text: "Kanal yok", detailText: "Telefonda M3U / Xtream ekleyin")
            ])]
        }

        let grouped = Dictionary(grouping: channels, by: \.groupTitle)
        let keys = grouped.keys.sorted {
            if $0 == "Uncategorized" { return false }
            if $1 == "Uncategorized" { return true }
            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        var result: [CPListSection] = []
        var budget = maxListItems
        for key in keys {
            guard budget > 0 else { break }
            let list = grouped[key] ?? []
            let slice = Array(list.prefix(budget))
            budget -= slice.count
            let items = slice.map { listItem(for: $0, queue: channels) }
            result.append(
                CPListSection(
                    items: items,
                    header: "\(key) (\(list.count))",
                    sectionIndexTitle: String(key.prefix(1)).uppercased()
                )
            )
        }
        return result
    }

    @MainActor
    private func categorySections() -> [CPListSection] {
        let all = allChannelsCache
        if all.isEmpty {
            return [CPListSection(items: [CPListItem(text: "Kategori yok", detailText: nil)])]
        }

        let grouped = Dictionary(grouping: all, by: \.groupTitle)
        let keys = grouped.keys.sorted {
            if $0 == "Uncategorized" { return false }
            if $1 == "Uncategorized" { return true }
            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        let allItem = CPListItem(text: "Tüm kanallar", detailText: "\(all.count) kanal")
        allItem.setImage(UIImage(systemName: "list.bullet"))
        allItem.handler = { [weak self] _, completion in
            Task { @MainActor in
                if let channels = self?.channelsTemplate {
                    self?.interfaceController?.push(template: channels, animated: true)
                }
                completion()
            }
        }

        let items: [CPListItem] = keys.map { key in
            let list = grouped[key] ?? []
            let item = CPListItem(text: key, detailText: "\(list.count) kanal")
            item.setImage(UIImage(systemName: "folder.fill"))
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    let detail = CPListTemplate(
                        title: key,
                        sections: self?.sections(for: list, empty: "Boş") ?? []
                    )
                    self?.interfaceController?.push(template: detail, animated: true)
                    completion()
                }
            }
            return item
        }

        return [CPListSection(items: [allItem] + items)]
    }

    @MainActor
    private func listItem(for channel: PlayableChannel, queue: [PlayableChannel]) -> CPListItem {
        let epg = EPGService.shared.nowAndNext(for: channel.tvgId)
        let detail: String
        if let now = epg.now {
            let end = now.stop.formatted(date: .omitted, time: .shortened)
            detail = "▶ \(now.title) · \(end)"
        } else if let next = epg.next {
            detail = "Sonra: \(next.title)"
        } else {
            detail = channel.groupTitle
        }

        let item = CPListItem(text: channel.name, detailText: detail)
        item.setImage(UIImage(systemName: "tv.circle.fill"))

        if playback.current?.url == channel.url {
            item.playingIndicatorLocation = .leading
        }

        item.handler = { [weak self] _, completion in
            Task { @MainActor in
                self?.playback.play(channel, in: queue)
                // Now Playing sekmesi / sistem Now Playing butonu otomatik güncellenir
                completion()
            }
        }

        if let logo = channel.logo, let url = URL(string: logo) {
            Task {
                if let image = await Self.downloadImage(url) {
                    await MainActor.run { item.setImage(image) }
                }
            }
        }

        return item
    }

    // MARK: - Search

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        updatedSearchText searchText: String,
        completionHandler: @escaping ([CPListItem]) -> Void
    ) {
        Task { @MainActor in
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = self.allChannelsCache.isEmpty
                ? PersistenceController.shared.allEnabledChannels()
                : self.allChannelsCache

            let filtered: [PlayableChannel]
            if q.isEmpty {
                filtered = Array(source.prefix(40))
            } else {
                filtered = Array(
                    source.filter {
                        $0.name.localizedCaseInsensitiveContains(q)
                            || $0.groupTitle.localizedCaseInsensitiveContains(q)
                            || ($0.tvgId?.localizedCaseInsensitiveContains(q) ?? false)
                    }
                    .prefix(self.maxListItems)
                )
            }
            completionHandler(filtered.map { self.listItem(for: $0, queue: filtered) })
        }
    }

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        selectedResult item: CPListItem,
        completionHandler: @escaping () -> Void
    ) {
        // Oynatma list item handler içinde
        completionHandler()
    }

    // MARK: - Now Playing controls

    @MainActor
    private func configureNowPlayingButtons() {
        let nowPlaying = CPNowPlayingTemplate.shared

        let previous = CPNowPlayingImageButton(image: UIImage(systemName: "backward.fill")!) { [weak self] _ in
            Task { @MainActor in self?.playback.playPrevious() }
        }
        let next = CPNowPlayingImageButton(image: UIImage(systemName: "forward.fill")!) { [weak self] _ in
            Task { @MainActor in self?.playback.playNext() }
        }
        let favorite = CPNowPlayingImageButton(image: UIImage(systemName: "star.fill")!) { [weak self] _ in
            Task { @MainActor in
                guard let channel = self?.playback.current else { return }
                PersistenceController.shared.toggleFavorite(channel)
                self?.reloadLists()
            }
        }
        let refresh = CPNowPlayingImageButton(image: UIImage(systemName: "arrow.clockwise")!) { [weak self] _ in
            Task { @MainActor in
                guard let self, let channel = self.playback.current else { return }
                self.playback.play(channel, in: self.playback.queue)
            }
        }

        nowPlaying.updateNowPlayingButtons([previous, favorite, refresh, next])
    }

    private static func downloadImage(_ url: URL) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
