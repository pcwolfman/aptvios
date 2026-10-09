import Foundation

// MARK: - Models

struct XtreamAccount: Codable, Hashable {
    var username: String?
    var password: String?
    var message: String?
    var auth: Int?
    var status: String?
    var expDate: String?
    var isTrial: String?
    var activeCons: String?
    var maxConnections: String?
    var allowedOutputFormats: [String]?

    enum CodingKeys: String, CodingKey {
        case username, password, message, auth, status
        case expDate = "exp_date"
        case isTrial = "is_trial"
        case activeCons = "active_cons"
        case maxConnections = "max_connections"
        case allowedOutputFormats = "allowed_output_formats"
    }

    var isAuthenticated: Bool {
        auth == 1 || status?.lowercased() == "active"
    }
}

struct XtreamCategory: Codable, Hashable, Identifiable {
    var categoryId: String
    var categoryName: String
    var parentId: Int?

    var id: String { categoryId }

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
        case parentId = "parent_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryId = try container.decodeFlexibleString(forKey: .categoryId)
        categoryName = try container.decode(String.self, forKey: .categoryName)
        parentId = try container.decodeIfPresent(Int.self, forKey: .parentId)
    }
}

struct XtreamStream: Codable, Hashable, Identifiable {
    var num: Int?
    var name: String
    var streamType: String?
    var streamId: Int
    var streamIcon: String?
    var epgChannelId: String?
    var categoryId: String?
    var categoryName: String?

    var id: Int { streamId }

    enum CodingKeys: String, CodingKey {
        case num, name
        case streamType = "stream_type"
        case streamId = "stream_id"
        case streamIcon = "stream_icon"
        case epgChannelId = "epg_channel_id"
        case categoryId = "category_id"
        case categoryName = "category_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        num = try container.decodeIfPresent(Int.self, forKey: .num)
        name = try container.decode(String.self, forKey: .name)
        streamType = try container.decodeIfPresent(String.self, forKey: .streamType)
        streamId = try container.decodeFlexibleInt(forKey: .streamId)
        streamIcon = try container.decodeIfPresent(String.self, forKey: .streamIcon)
        epgChannelId = try container.decodeIfPresent(String.self, forKey: .epgChannelId)
        categoryId = try container.decodeIfPresentFlexibleString(forKey: .categoryId)
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
    }
}

struct XtreamEPGListing: Codable, Hashable {
    var id: String?
    var epgId: String?
    var title: String?
    var lang: String?
    var start: String?
    var end: String?
    var description: String?
    var channelId: String?
    var startTimestamp: String?
    var stopTimestamp: String?

    enum CodingKeys: String, CodingKey {
        case id, title, lang, start, end, description
        case epgId = "epg_id"
        case channelId = "channel_id"
        case startTimestamp = "start_timestamp"
        case stopTimestamp = "stop_timestamp"
    }
}

enum XtreamStreamExtension: String, Sendable {
    case ts
    case m3u8
}

enum XtreamClientError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpError(Int)
    case authenticationFailed(String?)
    case decodeFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Geçersiz Xtream sunucu adresi"
        case .invalidResponse:
            return "Xtream sunucusundan geçersiz yanıt"
        case .httpError(let code):
            return "Xtream HTTP hatası: \(code)"
        case .authenticationFailed(let message):
            if let message, !message.isEmpty {
                return "Xtream kimlik doğrulama başarısız: \(message)"
            }
            return "Xtream kimlik doğrulama başarısız"
        case .decodeFailed(let detail):
            return "Xtream verisi okunamadı: \(detail)"
        case .networkError(let detail):
            return "Xtream ağ hatası: \(detail)"
        }
    }
}

// MARK: - Client

actor XtreamClient {
    private let baseURL: URL
    private let username: String
    private let password: String
    private let session: URLSession
    private var cachedAccount: XtreamAccount?

    init(baseURL: String, username: String, password: String, session: URLSession? = nil) throws {
        guard let url = XtreamClient.normalizedBaseURL(from: baseURL) else {
            throw XtreamClientError.invalidBaseURL
        }
        self.baseURL = url
        self.username = username
        self.password = password
        self.session = session ?? URLSession(configuration: ProxySession.shared.configuration)
    }

    func authenticate() async throws -> XtreamAccount {
        let response: XtreamAuthResponse = try await request(action: nil)
        guard let account = response.userInfo else {
            throw XtreamClientError.authenticationFailed(response.userInfo?.message)
        }
        guard account.isAuthenticated else {
            throw XtreamClientError.authenticationFailed(account.message ?? account.status)
        }
        cachedAccount = account
        return account
    }

    func getAccount() async throws -> XtreamAccount {
        if let cachedAccount { return cachedAccount }
        return try await authenticate()
    }

    func getLiveCategories() async throws -> [XtreamCategory] {
        try await request(action: "get_live_categories")
    }

    func getLiveStreams(categoryId: String? = nil) async throws -> [XtreamStream] {
        var query: [String: String] = [:]
        if let categoryId, !categoryId.isEmpty {
            query["category_id"] = categoryId
        }
        return try await request(action: "get_live_streams", extraQuery: query)
    }

    func getEPG(streamId: Int, limit: Int = 48) async throws -> [EPGProgram] {
        let listings: XtreamEPGResponse = try await request(
            action: "get_short_epg",
            extraQuery: [
                "stream_id": String(streamId),
                "limit": String(max(1, limit))
            ]
        )
        let channelKey = String(streamId)
        return listings.epgListings?.compactMap { listing in
            listing.asEPGProgram(fallbackChannelId: channelKey)
        } ?? []
    }

    func buildStreamURL(streamId: Int, extension ext: XtreamStreamExtension = .m3u8) -> String {
        Self.makeStreamURL(
            baseURL: baseURL,
            username: username,
            password: password,
            streamId: streamId,
            ext: ext
        )
    }

    func fetchParsedChannels(categoryId: String? = nil, streamExtension: XtreamStreamExtension = .m3u8) async throws -> [ParsedChannel] {
        let categories = try await getLiveCategories()
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.categoryId, $0.categoryName) })
        let streams = try await getLiveStreams(categoryId: categoryId)
        return streams.map { stream in
            stream.asParsedChannel(
                streamURL: buildStreamURL(streamId: stream.streamId, extension: streamExtension),
                categoryNames: categoryNames
            )
        }
    }

    // MARK: - Private

    private func request<T: Decodable>(
        action: String?,
        extraQuery: [String: String] = [:]
    ) async throws -> T {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("player_api.php"),
            resolvingAgainstBaseURL: false
        ) else {
            throw XtreamClientError.invalidBaseURL
        }

        var items = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        if let action {
            items.append(URLQueryItem(name: "action", value: action))
        }
        for (key, value) in extraQuery.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items

        guard let url = components.url else {
            throw XtreamClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(AppSettings.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,*/*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw XtreamClientError.httpError(http.statusCode)
            }
            guard !data.isEmpty else {
                throw XtreamClientError.invalidResponse
            }

            let decoder = JSONDecoder()
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw XtreamClientError.decodeFailed(error.localizedDescription)
            }
        } catch let error as XtreamClientError {
            throw error
        } catch {
            throw XtreamClientError.networkError(error.localizedDescription)
        }
    }

    static func makeStreamURL(
        baseURL: URL,
        username: String,
        password: String,
        streamId: Int,
        ext: XtreamStreamExtension
    ) -> String {
        let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let encodedPass = password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? password
        return "\(baseURL.absoluteString)/live/\(encodedUser)/\(encodedPass)/\(streamId).\(ext.rawValue)"
    }

    private static func normalizedBaseURL(from raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "http://\(trimmed)"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return URL(string: trimmed)
    }
}

// MARK: - Response wrappers

private struct XtreamAuthResponse: Decodable {
    var userInfo: XtreamAccount?
    var serverInfo: [String: String]?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }
}

private struct XtreamEPGResponse: Decodable {
    var epgListings: [XtreamEPGListing]?

    enum CodingKeys: String, CodingKey {
        case epgListings = "epg_listings"
    }
}

// MARK: - Conversions

extension XtreamStream {
    func asParsedChannel(streamURL: String, categoryNames: [String: String]) -> ParsedChannel {
        let group = categoryName
            ?? categoryId.flatMap { categoryNames[$0] }
            ?? "Uncategorized"
        let tvg = epgChannelId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? String(streamId)
        return ParsedChannel(
            name: name,
            url: streamURL,
            logo: streamIcon?.nilIfEmpty,
            groupTitle: group,
            tvgId: tvg,
            tvgName: name
        )
    }
}

extension XtreamEPGListing {
    func asEPGProgram(fallbackChannelId: String) -> EPGProgram? {
        let channelKey = channelId?.nilIfEmpty ?? fallbackChannelId
        guard let startDate = DIYPDateParser.parseAny(start ?? startTimestamp),
              let stopDate = DIYPDateParser.parseAny(end ?? stopTimestamp) else {
            return nil
        }
        let programTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Program"
        return EPGProgram(
            channelId: channelKey,
            title: programTitle,
            desc: description?.nilIfEmpty,
            start: startDate,
            stop: stopDate
        )
    }
}

// MARK: - Decoding helpers

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(codingPath: [key], debugDescription: "Expected String or Int")
        )
    }

    func decodeIfPresentFlexibleString(forKey key: Key) throws -> String? {
        if (try? decodeNil(forKey: key)) == true { return nil }
        return try decodeFlexibleString(forKey: key)
    }

    func decodeFlexibleInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key), let intValue = Int(value) {
            return intValue
        }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(codingPath: [key], debugDescription: "Expected Int or numeric String")
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
