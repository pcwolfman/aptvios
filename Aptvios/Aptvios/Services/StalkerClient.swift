import Foundation

// MARK: - Limitations
//
// Stalker Middleware portals vary widely by provider firmware and custom patches.
// This client implements the common MAG-style load.php flow:
//   handshake -> get_profile -> get_genres -> get_ordered_list -> create_link
//
// Known limitations:
// - Only live ITV channels are fetched; VOD/series/radio are not supported.
// - Some portals require portal.php, stalker_portal/c/, or pre-shared serial numbers.
// - create_link responses differ; we accept plain strings, js.cmd, or js.url fields.
// - Pagination stops after empty pages or a safety cap; very large bouquets may truncate.
// - MAC address must often be whitelisted on the server; random MACs may be rejected.
// - Cookie / Bearer token handling is best-effort and may need provider-specific tuning.

enum StalkerClientError: LocalizedError {
    case invalidPortalURL
    case handshakeFailed(String?)
    case httpError(Int)
    case decodeFailed(String)
    case networkError(String)
    case noChannels
    case createLinkFailed(String?)

    var errorDescription: String? {
        switch self {
        case .invalidPortalURL:
            return "Geçersiz Stalker portal adresi"
        case .handshakeFailed(let detail):
            if let detail, !detail.isEmpty {
                return "Stalker el sıkışma hatası: \(detail)"
            }
            return "Stalker el sıkışma başarısız"
        case .httpError(let code):
            return "Stalker HTTP hatası: \(code)"
        case .decodeFailed(let detail):
            return "Stalker verisi okunamadı: \(detail)"
        case .networkError(let detail):
            return "Stalker ağ hatası: \(detail)"
        case .noChannels:
            return "Stalker kanal listesi boş"
        case .createLinkFailed(let detail):
            if let detail, !detail.isEmpty {
                return "Stalker yayın linki alınamadı: \(detail)"
            }
            return "Stalker yayın linki alınamadı"
        }
    }
}

struct StalkerGenre: Hashable, Identifiable {
    let id: String
    let title: String
}

struct StalkerChannelEntry: Hashable, Identifiable {
    let id: String
    let name: String
    let cmd: String
    let logo: String?
    let genreTitle: String
}

actor StalkerClient {
    private let portalURL: URL
    private let macAddress: String
    private let timezone: String
    private let session: URLSession

    private var token: String?
    private var randomToken: String?

    init(
        portalURL: String,
        macAddress: String? = nil,
        timezone: String = "Europe/Istanbul",
        session: URLSession? = nil
    ) throws {
        guard let url = StalkerClient.normalizedPortalURL(from: portalURL) else {
            throw StalkerClientError.invalidPortalURL
        }
        self.portalURL = url
        self.macAddress = macAddress ?? StalkerClient.generateMAC()
        self.timezone = timezone
        self.session = session ?? URLSession(configuration: ProxySession.shared.configuration)
    }

    func connect() async throws {
        try await handshake()
        _ = try await getProfile()
    }

    func fetchParsedChannels() async throws -> [ParsedChannel] {
        try await connect()
        let genres = try await getGenres()
        var entries: [StalkerChannelEntry] = []

        if genres.isEmpty {
            entries = try await getOrderedList(genreId: "*", genreTitle: "Live TV")
        } else {
            for genre in genres {
                let pageEntries = try await getOrderedList(genreId: genre.id, genreTitle: genre.title)
                entries.append(contentsOf: pageEntries)
            }
        }

        guard !entries.isEmpty else {
            throw StalkerClientError.noChannels
        }

        var channels: [ParsedChannel] = []
        channels.reserveCapacity(entries.count)

        for entry in entries {
            let playURL = try await createLink(cmd: entry.cmd)
            channels.append(
                ParsedChannel(
                    name: entry.name,
                    url: playURL,
                    logo: entry.logo,
                    groupTitle: entry.genreTitle,
                    tvgId: entry.id,
                    tvgName: entry.name
                )
            )
        }

        return channels
    }

    // MARK: - Stalker actions

    func handshake() async throws {
        let response: StalkerEnvelope<StalkerHandshakePayload> = try await load(
            type: "stb",
            action: "handshake",
            query: ["token": ""]
        )
        guard let payload = response.payload, payload.notValid != 1 else {
            throw StalkerClientError.handshakeFailed(response.payload?.message)
        }
        token = payload.token
        randomToken = payload.random
    }

    func getProfile() async throws -> [String: AnyJSONValue] {
        let response: StalkerEnvelope<[String: AnyJSONValue]> = try await load(type: "stb", action: "get_profile")
        return response.payload ?? [:]
    }

    func getGenres() async throws -> [StalkerGenre] {
        let response: StalkerEnvelope<[StalkerGenreDTO]> = try await load(type: "itv", action: "get_genres")
        return response.payload?.map {
            StalkerGenre(id: $0.id, title: $0.title.nilIfEmpty ?? "Live TV")
        } ?? []
    }

    func getOrderedList(genreId: String, genreTitle: String) async throws -> [StalkerChannelEntry] {
        var page = 1
        var collected: [StalkerChannelEntry] = []
        let maxPages = 50

        while page <= maxPages {
            let response: StalkerEnvelope<StalkerOrderedListPayload> = try await load(
                type: "itv",
                action: "get_ordered_list",
                query: [
                    "genre": genreId,
                    "p": String(page)
                ]
            )
            let data = response.payload?.data ?? []
            if data.isEmpty { break }

            collected.append(contentsOf: data.map { item in
                StalkerChannelEntry(
                    id: item.id,
                    name: item.name.nilIfEmpty ?? "Channel",
                    cmd: item.cmd ?? "",
                    logo: item.logo?.nilIfEmpty,
                    genreTitle: genreTitle
                )
            })

            if data.count < 14 { break }
            page += 1
        }

        return collected.filter { !$0.cmd.isEmpty }
    }

    func createLink(cmd: String) async throws -> String {
        guard !cmd.isEmpty else {
            throw StalkerClientError.createLinkFailed("Boş cmd")
        }

        let response: StalkerEnvelope<StalkerCreateLinkPayload> = try await load(
            type: "itv",
            action: "create_link",
            query: ["cmd": cmd]
        )

        if let url = response.payload?.resolvedURL?.nilIfEmpty {
            return url
        }
        if let jsString = response.jsString?.nilIfEmpty {
            return jsString
        }
        throw StalkerClientError.createLinkFailed(response.payload?.error)
    }

    // MARK: - Networking

    private func load<T: Decodable>(
        type: String,
        action: String,
        query: [String: String] = [:]
    ) async throws -> T {
        guard var components = URLComponents(url: portalURL, resolvingAgainstBaseURL: false) else {
            throw StalkerClientError.invalidPortalURL
        }

        var items = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "JsHttpRequest", value: "1-xml")
        ]
        for (key, value) in query.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items

        guard let url = components.url else {
            throw StalkerClientError.invalidPortalURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue(StalkerClient.magUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Model: MAG254; Link: Ethernet", forHTTPHeaderField: "X-User-Agent")
        request.setValue("application/json,*/*", forHTTPHeaderField: "Accept")
        request.setValue(buildReferer(), forHTTPHeaderField: "Referer")
        request.setValue(buildCookie(), forHTTPHeaderField: "Cookie")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw StalkerClientError.httpError(http.statusCode)
            }

            let decoder = JSONDecoder()
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw StalkerClientError.decodeFailed(error.localizedDescription)
            }
        } catch let error as StalkerClientError {
            throw error
        } catch {
            throw StalkerClientError.networkError(error.localizedDescription)
        }
    }

    private func buildCookie() -> String {
        var parts = [
            "mac=\(macAddress)",
            "stb_lang=en",
            "timezone=\(timezone)"
        ]
        if let randomToken {
            parts.append("random=\(randomToken)")
        }
        return parts.joined(separator: "; ")
    }

    private func buildReferer() -> String {
        var base = portalURL.absoluteString
        if base.hasSuffix("load.php") {
            base = String(base.dropLast("load.php".count))
        }
        if !base.hasSuffix("/") {
            base += "/"
        }
        return base + "c/"
    }

    private static let magUserAgent =
        "Mozilla/5.0 (QtEmbedded; U; Linux; C) MAG200 stbapp ver: 2 rev: 250 Safari/534.1"

    private static func normalizedPortalURL(from raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "http://\(trimmed)"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        if trimmed.lowercased().hasSuffix("load.php") {
            return URL(string: trimmed)
        }

        if trimmed.lowercased().hasSuffix("/c") {
            trimmed += "/portal.php"
        } else if !trimmed.lowercased().contains("portal.php") {
            trimmed += "/portal.php"
        }

        guard var components = URLComponents(string: trimmed) else { return nil }
        components.path = components.path.replacingOccurrences(of: "/portal.php", with: "/load.php")
        if !components.path.lowercased().hasSuffix("load.php") {
            components.path = (components.path as NSString).deletingLastPathComponent + "/load.php"
        }
        return components.url
    }

    private static func generateMAC() -> String {
        var bytes = (0..<3).map { _ in UInt8.random(in: 0...255) }
        bytes[0] = 0x00
        bytes[1] = 0x1A
        bytes[2] = 0x79
        let tail = (0..<3).map { _ in UInt8.random(in: 0...255) }
        let all = bytes + tail
        return all.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

// MARK: - DTOs

private struct StalkerEnvelope<T: Decodable>: Decodable {
    var js: T?
    var payload: T? { js }
    var jsString: String?

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let text = try? container.decode(String.self) {
            jsString = text
            js = nil
            return
        }

        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        if container.contains(DynamicCodingKey("js")) {
            js = try container.decode(T.self, forKey: DynamicCodingKey("js"))
        } else {
            js = try T(from: decoder)
        }
    }
}

private struct StalkerHandshakePayload: Decodable {
    var token: String?
    var random: String?
    var notValid: Int?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case token, random, message
        case notValid = "not_valid"
    }
}

private struct StalkerGenreDTO: Decodable {
    var id: String
    var title: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        id = try StalkerFlexibleDecoder.string(from: container, keys: ["id", "genre_id", "num"])
        title = try StalkerFlexibleDecoder.string(from: container, keys: ["title", "name", "genre_title"])
    }
}

private struct StalkerOrderedListPayload: Decodable {
    var data: [StalkerChannelDTO]?
}

private struct StalkerChannelDTO: Decodable {
    var id: String
    var name: String
    var cmd: String?
    var logo: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        id = try StalkerFlexibleDecoder.string(from: container, keys: ["id", "ch_id", "num"])
        name = try StalkerFlexibleDecoder.string(from: container, keys: ["name", "title"])
        cmd = try StalkerFlexibleDecoder.optionalString(from: container, keys: ["cmd", "url", "stream_url"])
        logo = try StalkerFlexibleDecoder.optionalString(from: container, keys: ["logo", "screenshot_uri", "pic"])
    }
}

private struct StalkerCreateLinkPayload: Decodable {
    var cmd: String?
    var url: String?
    var error: String?

    var resolvedURL: String? {
        cmd?.nilIfEmpty ?? url?.nilIfEmpty
    }
}

private enum StalkerFlexibleDecoder {
    static func string(from container: KeyedDecodingContainer<DynamicCodingKey>, keys: [String]) throws -> String {
        for key in keys {
            let codingKey = DynamicCodingKey(key)
            if let value = try? container.decode(String.self, forKey: codingKey) {
                return value
            }
            if let value = try? container.decode(Int.self, forKey: codingKey) {
                return String(value)
            }
        }
        return ""
    }

    static func optionalString(from container: KeyedDecodingContainer<DynamicCodingKey>, keys: [String]) throws -> String? {
        for key in keys {
            let codingKey = DynamicCodingKey(key)
            if let value = try? container.decode(String.self, forKey: codingKey) {
                return value.nilIfEmpty
            }
            if let value = try? container.decode(Int.self, forKey: codingKey) {
                return String(value)
            }
        }
        return nil
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.intValue = intValue
        stringValue = String(intValue)
    }
}

enum AnyJSONValue: Decodable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyJSONValue])
    case array([AnyJSONValue])
    case null

    init(from decoder: Decoder) throws {
        if var arrayContainer = try? decoder.unkeyedContainer() {
            var values: [AnyJSONValue] = []
            while !arrayContainer.isAtEnd {
                values.append(try arrayContainer.decode(AnyJSONValue.self))
            }
            self = .array(values)
            return
        }

        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var dict: [String: AnyJSONValue] = [:]
            for key in container.allKeys {
                dict[key.stringValue] = try container.decode(AnyJSONValue.self, forKey: key)
            }
            self = .object(dict)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
