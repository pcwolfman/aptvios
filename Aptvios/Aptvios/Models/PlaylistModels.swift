import Foundation

struct ParsedChannel: Identifiable, Hashable, Codable {
    var id: String { key }
    var name: String
    var url: String
    var logo: String?
    var groupTitle: String
    var tvgId: String?
    var tvgName: String?
    var userAgent: String?
    var referer: String?

    var key: String { url }

    init(
        name: String,
        url: String,
        logo: String? = nil,
        groupTitle: String = "Uncategorized",
        tvgId: String? = nil,
        tvgName: String? = nil,
        userAgent: String? = nil,
        referer: String? = nil
    ) {
        self.name = name
        self.url = url
        self.logo = logo
        self.groupTitle = groupTitle.isEmpty ? "Uncategorized" : groupTitle
        self.tvgId = tvgId
        self.tvgName = tvgName
        self.userAgent = userAgent
        self.referer = referer
    }
}

struct PlayableChannel: Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var logo: String?
    var groupTitle: String
    var tvgId: String?
    var userAgent: String?
    var referer: String?
    var sourceName: String?

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        logo: String? = nil,
        groupTitle: String = "Uncategorized",
        tvgId: String? = nil,
        userAgent: String? = nil,
        referer: String? = nil,
        sourceName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.logo = logo
        self.groupTitle = groupTitle
        self.tvgId = tvgId
        self.userAgent = userAgent
        self.referer = referer
        self.sourceName = sourceName
    }

    init(from item: ChannelItem) {
        self.id = item.id ?? UUID()
        self.name = item.name ?? "Channel"
        self.url = item.url ?? ""
        self.logo = item.logo
        self.groupTitle = item.groupTitle ?? "Uncategorized"
        self.tvgId = item.tvgId
        self.userAgent = item.userAgent
        self.referer = item.referer
        self.sourceName = item.config?.name
    }

    init(from parsed: ParsedChannel, sourceName: String? = nil) {
        self.id = UUID()
        self.name = parsed.name
        self.url = parsed.url
        self.logo = parsed.logo
        self.groupTitle = parsed.groupTitle
        self.tvgId = parsed.tvgId
        self.userAgent = parsed.userAgent
        self.referer = parsed.referer
        self.sourceName = sourceName
    }
}

enum PlaylistFormat: String, CaseIterable, Identifiable {
    case auto
    case m3u
    case txt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .m3u: return "M3U"
        case .txt: return "TXT"
        }
    }
}

struct EPGProgram: Identifiable, Hashable {
    let id: UUID
    var channelId: String
    var title: String
    var desc: String?
    var start: Date
    var stop: Date

    init(
        id: UUID = UUID(),
        channelId: String,
        title: String,
        desc: String? = nil,
        start: Date,
        stop: Date
    ) {
        self.id = id
        self.channelId = channelId
        self.title = title
        self.desc = desc
        self.start = start
        self.stop = stop
    }

    var isNow: Bool {
        let now = Date()
        return start <= now && now < stop
    }
}

enum AptviosError: LocalizedError {
    case invalidURL
    case emptyPlaylist
    case downloadFailed(String)
    case parseFailed(String)
    case noChannels

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Geçersiz URL"
        case .emptyPlaylist: return "Playlist boş"
        case .downloadFailed(let m): return "İndirme hatası: \(m)"
        case .parseFailed(let m): return "Ayrıştırma hatası: \(m)"
        case .noChannels: return "Kanal bulunamadı"
        }
    }
}
