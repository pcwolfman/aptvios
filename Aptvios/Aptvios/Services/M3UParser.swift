import Foundation

enum PlaylistParser {
    static func detectFormat(_ text: String) -> PlaylistFormat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().contains("#EXTM3U") || trimmed.uppercased().contains("#EXTINF") {
            return .m3u
        }
        // TXT style: Group,ChannelName,URL
        let lines = trimmed.split(whereSeparator: \.isNewline)
        if lines.contains(where: { $0.contains(",") && ($0.contains("http://") || $0.contains("https://")) }) {
            return .txt
        }
        return .m3u
    }

    static func parse(_ text: String, format: PlaylistFormat = .auto) throws -> [ParsedChannel] {
        let resolved: PlaylistFormat
        switch format {
        case .auto: resolved = detectFormat(text)
        default: resolved = format
        }

        let channels: [ParsedChannel]
        switch resolved {
        case .m3u, .auto:
            channels = try parseM3U(text)
        case .txt:
            channels = try parseTXT(text)
        }

        guard !channels.isEmpty else { throw AptviosError.noChannels }
        return channels
    }

    // MARK: - M3U

    static func parseM3U(_ text: String) throws -> [ParsedChannel] {
        var channels: [ParsedChannel] = []
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var pendingName = ""
        var pendingLogo: String?
        var pendingGroup = "Uncategorized"
        var pendingTvgId: String?
        var pendingTvgName: String?
        var pendingUA: String?
        var pendingReferer: String?
        var hasExtinf = false

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let upper = line.uppercased()
            if upper.hasPrefix("#EXTM3U") { continue }

            if upper.hasPrefix("#EXTVLCOPT:") {
                let value = String(line.dropFirst("#EXTVLCOPT:".count)).trimmingCharacters(in: .whitespaces)
                if value.lowercased().hasPrefix("http-user-agent=") {
                    pendingUA = String(value.dropFirst("http-user-agent=".count))
                } else if value.lowercased().hasPrefix("http-referrer=") {
                    pendingReferer = String(value.dropFirst("http-referrer=".count))
                } else if value.lowercased().hasPrefix("http-referer=") {
                    pendingReferer = String(value.dropFirst("http-referer=".count))
                }
                continue
            }

            if upper.hasPrefix("#EXTINF:") {
                hasExtinf = true
                let attrs = parseExtInf(line)
                pendingName = attrs.name
                pendingLogo = attrs.logo
                pendingGroup = attrs.group
                pendingTvgId = attrs.tvgId
                pendingTvgName = attrs.tvgName
                if let ua = attrs.userAgent { pendingUA = ua }
                if let ref = attrs.referer { pendingReferer = ref }
                continue
            }

            if line.hasPrefix("#") { continue }

            if hasExtinf || looksLikeURL(line) {
                let name = pendingName.isEmpty ? (URL(string: line)?.lastPathComponent ?? "Channel") : pendingName
                channels.append(
                    ParsedChannel(
                        name: name,
                        url: line,
                        logo: pendingLogo,
                        groupTitle: pendingGroup,
                        tvgId: pendingTvgId,
                        tvgName: pendingTvgName,
                        userAgent: pendingUA,
                        referer: pendingReferer
                    )
                )
                pendingName = ""
                pendingLogo = nil
                pendingGroup = "Uncategorized"
                pendingTvgId = nil
                pendingTvgName = nil
                pendingUA = nil
                pendingReferer = nil
                hasExtinf = false
            }
        }

        return channels
    }

    private struct ExtInfAttrs {
        var name: String
        var logo: String?
        var group: String
        var tvgId: String?
        var tvgName: String?
        var userAgent: String?
        var referer: String?
    }

    private static func parseExtInf(_ line: String) -> ExtInfAttrs {
        // #EXTINF:-1 tvg-id="x" tvg-logo="y" group-title="z",Channel Name
        var name = "Channel"
        if let comma = line.lastIndex(of: ",") {
            name = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        }

        func attr(_ key: String) -> String? {
            let patterns = [
                "\(key)=\"([^\"]*)\"",
                "\(key)='([^']*)'"
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    if let match = regex.firstMatch(in: line, options: [], range: range),
                       match.numberOfRanges > 1,
                       let r = Range(match.range(at: 1), in: line) {
                        let value = String(line[r])
                        return value.isEmpty ? nil : value
                    }
                }
            }
            return nil
        }

        return ExtInfAttrs(
            name: name.isEmpty ? "Channel" : name,
            logo: attr("tvg-logo") ?? attr("logo"),
            group: attr("group-title") ?? attr("group") ?? "Uncategorized",
            tvgId: attr("tvg-id"),
            tvgName: attr("tvg-name"),
            userAgent: attr("user-agent") ?? attr("http-user-agent"),
            referer: attr("referrer") ?? attr("referer") ?? attr("http-referrer")
        )
    }

    // MARK: - TXT (genre,name,url OR name,url)

    static func parseTXT(_ text: String) throws -> [ParsedChannel] {
        var channels: [ParsedChannel] = []
        var currentGroup = "Uncategorized"

        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }

            // Group header: GenreName,#genre#
            if line.lowercased().contains("#genre#") {
                let parts = line.components(separatedBy: ",")
                if let first = parts.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty {
                    currentGroup = first
                }
                continue
            }

            let parts = splitCSV(line)
            guard !parts.isEmpty else { continue }

            if parts.count >= 3, looksLikeURL(parts[2]) {
                channels.append(
                    ParsedChannel(
                        name: parts[1].isEmpty ? parts[0] : parts[1],
                        url: parts[2],
                        groupTitle: parts[0].isEmpty ? currentGroup : parts[0]
                    )
                )
            } else if parts.count >= 2, looksLikeURL(parts[1]) {
                channels.append(
                    ParsedChannel(
                        name: parts[0].isEmpty ? "Channel" : parts[0],
                        url: parts[1],
                        groupTitle: currentGroup
                    )
                )
            } else if parts.count == 1, looksLikeURL(parts[0]) {
                channels.append(
                    ParsedChannel(
                        name: URL(string: parts[0])?.lastPathComponent ?? "Channel",
                        url: parts[0],
                        groupTitle: currentGroup
                    )
                )
            }
        }

        return channels
    }

    private static func splitCSV(_ line: String) -> [String] {
        line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func looksLikeURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("rtmp://")
            || lower.hasPrefix("rtsp://")
            || lower.hasPrefix("udp://")
            || lower.hasPrefix("rtp://")
    }
}
