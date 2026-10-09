import Foundation

@MainActor
final class EPGService: ObservableObject {
    static let shared = EPGService()

    @Published private(set) var programsByChannel: [String: [EPGProgram]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdated: Date?

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("epg-cache.json")
    }

    func loadCached() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode(EPGCache.self, from: data) else { return }
        programsByChannel = decoded.programs
        lastUpdated = decoded.updatedAt
    }

    func refresh(from urlString: String, mode: EPGMode = .xmltv, channelIds: [String] = []) async {
        guard !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            switch mode {
            case .xmltv:
                try await refreshXMLTV(urlString)
            case .diyp:
                try await refreshDIYP(urlString, channelIds: channelIds)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshXMLTV(_ urlString: String) async throws {
        guard let url = URL(string: urlString) else { throw AptviosError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue(AppSettings.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: ProxySession.shared.configuration)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AptviosError.downloadFailed("HTTP \(http.statusCode)")
        }

        let xmlData: Data
        if urlString.lowercased().hasSuffix(".gz") || isGzip(data) {
            xmlData = try Gzip.decompress(data)
        } else {
            xmlData = data
        }

        programsByChannel = try XMLTVParser.parse(xmlData)
        lastUpdated = Date()
        saveCache()
    }

    private func refreshDIYP(_ baseURL: String, channelIds: [String]) async throws {
        let client = try DIYPEPGClient(epgBaseURL: baseURL)
        var merged: [String: [EPGProgram]] = programsByChannel
        let ids = channelIds.isEmpty
            ? Array(Set(PersistenceController.shared.allEnabledChannels().compactMap(\.tvgId))).prefix(80)
            : channelIds.prefix(80)

        for id in ids {
            if let programs = try? await client.fetchPrograms(for: id), !programs.isEmpty {
                merged[id] = programs
            }
        }
        programsByChannel = merged
        lastUpdated = Date()
        saveCache()
    }

    func nowAndNext(for tvgId: String?) -> (now: EPGProgram?, next: EPGProgram?) {
        guard let tvgId, let list = programsByChannel[tvgId] else { return (nil, nil) }
        let now = Date()
        let sorted = list.sorted { $0.start < $1.start }
        let current = sorted.first { $0.start <= now && now < $0.stop }
        let next = sorted.first { $0.start >= (current?.stop ?? now) }
        return (current, next)
    }

    private func saveCache() {
        let cache = EPGCache(updatedAt: lastUpdated ?? Date(), programs: programsByChannel)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[0] == 0x1f && data[1] == 0x8b
    }
}

private struct EPGCache: Codable {
    var updatedAt: Date
    var programs: [String: [EPGProgram]]
}

enum XMLTVParser {
    static func parse(_ data: Data) throws -> [String: [EPGProgram]] {
        let parser = XMLTVDelegate()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else {
            throw AptviosError.parseFailed(xml.parserError?.localizedDescription ?? "XMLTV")
        }
        return parser.programs
    }
}

private final class XMLTVDelegate: NSObject, XMLParserDelegate {
    var programs: [String: [EPGProgram]] = [:]

    private var currentElement = ""
    private var currentChannel = ""
    private var currentTitle = ""
    private var currentDesc = ""
    private var currentStart: Date?
    private var currentStop: Date?
    private var capturingTitle = false
    private var capturingDesc = false

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMddHHmmss Z"
        return f
    }()

    private let formatterNoTZ: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "programme" {
            currentChannel = attributeDict["channel"] ?? ""
            currentTitle = ""
            currentDesc = ""
            currentStart = parseDate(attributeDict["start"])
            currentStop = parseDate(attributeDict["stop"])
        } else if elementName == "title" {
            capturingTitle = true
        } else if elementName == "desc" {
            capturingDesc = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingTitle { currentTitle += string }
        if capturingDesc { currentDesc += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "title" { capturingTitle = false }
        if elementName == "desc" { capturingDesc = false }
        if elementName == "programme" {
            guard let start = currentStart, let stop = currentStop, !currentChannel.isEmpty else { return }
            let program = EPGProgram(
                channelId: currentChannel,
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Program"
                    : currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                desc: currentDesc.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                start: start,
                stop: stop
            )
            programs[currentChannel, default: []].append(program)
        }
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard var raw else { return nil }
        raw = raw.trimmingCharacters(in: .whitespaces)
        // "20240101120000 +0000" or "20240101120000 +0000"
        if raw.count >= 14 {
            let head = String(raw.prefix(14))
            let rest = raw.dropFirst(14).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                return formatterNoTZ.date(from: head)
            }
            let combined = "\(head) \(rest)"
            if let d = formatter.date(from: combined) { return d }
            // try without space issues
            let compact = raw.replacingOccurrences(of: "  ", with: " ")
            if compact.count > 14 {
                let h = String(compact.prefix(14))
                let t = compact.dropFirst(14).trimmingCharacters(in: .whitespaces)
                return formatter.date(from: "\(h) \(t)") ?? formatterNoTZ.date(from: h)
            }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
