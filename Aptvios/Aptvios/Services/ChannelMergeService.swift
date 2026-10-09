import Foundation

enum ChannelMergeService {
    /// Aynı isim / tvg-id / benzer URL’ye sahip kanalları birleştirir; ilk kaydın URL’sini tutar, alternatifleri not düşer.
    static func mergeDuplicates(_ channels: [ParsedChannel], strategy: Strategy = .byNameAndGroup) -> [ParsedChannel] {
        var map: [String: ParsedChannel] = [:]
        var order: [String] = []

        for channel in channels {
            let key: String
            switch strategy {
            case .byNameAndGroup:
                key = (channel.groupTitle + "|" + channel.name).lowercased()
            case .byTvgId:
                key = (channel.tvgId ?? channel.url).lowercased()
            case .byURLHostPath:
                key = normalizedURLKey(channel.url)
            }

            if map[key] == nil {
                map[key] = channel
                order.append(key)
            } else if map[key]?.logo == nil, let logo = channel.logo {
                var existing = map[key]!
                existing.logo = logo
                map[key] = existing
            }
        }
        return order.compactMap { map[$0] }
    }

    enum Strategy {
        case byNameAndGroup
        case byTvgId
        case byURLHostPath
    }

    private static func normalizedURLKey(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString.lowercased() }
        return ((url.host ?? "") + url.path).lowercased()
    }
}
