import Foundation

enum DIYPEPGClientError: LocalizedError {
    case invalidBaseURL
    case httpError(Int)
    case decodeFailed(String)
    case networkError(String)
    case noPrograms

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Geçersiz EPG adresi"
        case .httpError(let code):
            return "EPG HTTP hatası: \(code)"
        case .decodeFailed(let detail):
            return "EPG verisi okunamadı: \(detail)"
        case .networkError(let detail):
            return "EPG ağ hatası: \(detail)"
        case .noPrograms:
            return "EPG programı bulunamadı"
        }
    }
}

struct DIYPEPGClient {
    let epgBaseURL: URL
    let session: URLSession

    init(epgBaseURL: String, session: URLSession? = nil) throws {
        guard let url = DIYPEPGClient.normalizedBaseURL(from: epgBaseURL) else {
            throw DIYPEPGClientError.invalidBaseURL
        }
        self.epgBaseURL = url
        self.session = session ?? URLSession(configuration: ProxySession.shared.configuration)
    }

    func fetchPrograms(for channelId: String, date: Date = Date()) async throws -> [EPGProgram] {
        let dayString = DIYPDateParser.dayFormatter.string(from: date)
        let candidates = endpointCandidates(channelId: channelId, date: dayString)

        var lastError: Error?
        for url in candidates {
            do {
                let data = try await download(url)
                let programs = try parsePrograms(data: data, channelId: channelId)
                if !programs.isEmpty {
                    return programs.sorted { $0.start < $1.start }
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        throw DIYPEPGClientError.noPrograms
    }

    func fetchPrograms(
        for channelIds: [String],
        date: Date = Date()
    ) async throws -> [String: [EPGProgram]] {
        var result: [String: [EPGProgram]] = [:]
        for channelId in channelIds {
            let trimmed = channelId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let programs = try? await fetchPrograms(for: trimmed, date: date), !programs.isEmpty {
                result[trimmed] = programs
            }
        }
        return result
    }

    // MARK: - Endpoint building

    private func endpointCandidates(channelId: String, date: String) -> [URL] {
        var urls: [URL] = []
        let encodedChannel = channelId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? channelId
        let encodedDate = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? date

        let queryPatterns = [
            "ch=\(encodedChannel)&date=\(encodedDate)",
            "channel=\(encodedChannel)&date=\(encodedDate)",
            "id=\(encodedChannel)&date=\(encodedDate)",
            "tvg_id=\(encodedChannel)&date=\(encodedDate)",
            "c=\(encodedChannel)&d=\(encodedDate)"
        ]

        if var components = URLComponents(url: epgBaseURL, resolvingAgainstBaseURL: false) {
            for pattern in queryPatterns {
                var copy = components
                copy.query = pattern
                if let url = copy.url {
                    urls.append(url)
                }
            }

            if components.path.isEmpty || components.path == "/" {
                for suffix in ["epg", "api/epg", "diyp/epg"] {
                    var copy = components
                    copy.path = "/\(suffix)"
                    copy.query = "ch=\(encodedChannel)&date=\(encodedDate)"
                    if let url = copy.url {
                        urls.append(url)
                    }
                }
            }
        }

        return Array(Set(urls))
    }

    // MARK: - Download / parse

    private func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue(AppSettings.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,*/*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw DIYPEPGClientError.httpError(http.statusCode)
            }
            guard !data.isEmpty else {
                throw DIYPEPGClientError.noPrograms
            }
            return data
        } catch let error as DIYPEPGClientError {
            throw error
        } catch {
            throw DIYPEPGClientError.networkError(error.localizedDescription)
        }
    }

    private func parsePrograms(data: Data, channelId: String) throws -> [EPGProgram] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let array = try? decoder.decode([DIYPProgramDTO].self, from: data) {
            return array.compactMap { $0.asEPGProgram(channelId: channelId) }
        }

        if let wrapped = try? decoder.decode(DIYPWrappedPrograms.self, from: data) {
            let items = wrapped.resolvedPrograms
            return items.compactMap { $0.asEPGProgram(channelId: channelId) }
        }

        if let map = try? decoder.decode([String: [DIYPProgramDTO]].self, from: data) {
            let direct = map[channelId] ?? map.values.flatMap { $0 }
            return direct.compactMap { $0.asEPGProgram(channelId: channelId) }
        }

        throw DIYPEPGClientError.decodeFailed("Desteklenmeyen DIYP JSON formatı")
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

// MARK: - DTOs

private struct DIYPWrappedPrograms: Decodable {
    var programs: [DIYPProgramDTO]?
    var epg: [DIYPProgramDTO]?
    var data: [DIYPProgramDTO]?
    var list: [DIYPProgramDTO]?
    var channel: DIYPChannelPrograms?

    var resolvedPrograms: [DIYPProgramDTO] {
        if let programs { return programs }
        if let epg { return epg }
        if let data { return data }
        if let list { return list }
        if let channelPrograms = channel?.programs { return channelPrograms }
        return []
    }
}

private struct DIYPChannelPrograms: Decodable {
    var programs: [DIYPProgramDTO]?
}

private struct DIYPProgramDTO: Decodable {
    var title: String?
    var name: String?
    var desc: String?
    var description: String?
    var start: JSONScalar?
    var end: JSONScalar?
    var stop: JSONScalar?
    var startTime: JSONScalar?
    var endTime: JSONScalar?
    var channelId: String?

    func asEPGProgram(channelId fallbackChannelId: String) -> EPGProgram? {
        let channelKey = channelId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackChannelId
        guard let startDate = DIYPDateParser.parseAny(start?.stringValue ?? startTime?.stringValue),
              let stopDate = DIYPDateParser.parseAny(end?.stringValue ?? stop?.stringValue ?? endTime?.stringValue) else {
            return nil
        }

        let programTitle = (title ?? name)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Program"
        let programDesc = (desc ?? description)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        return EPGProgram(
            channelId: channelKey,
            title: programTitle,
            desc: programDesc,
            start: startDate,
            stop: stopDate
        )
    }
}

private enum JSONScalar: Decodable {
    case string(String)
    case int(Int)
    case double(Double)

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONScalar.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected scalar JSON value")
            )
        }
    }
}

enum DIYPDateParser {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let formatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy/MM/dd HH:mm:ss",
            "yyyyMMddHHmmss",
            "HH:mm:ss"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            return formatter
        }
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseAny(_ raw: String?) -> Date? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if let doubleValue = Double(value) {
            if doubleValue > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: doubleValue / 1000)
            }
            if doubleValue > 1_000_000_000 {
                return Date(timeIntervalSince1970: doubleValue)
            }
        }

        if let intValue = Int(value), intValue > 1_000_000_000 {
            if intValue > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: TimeInterval(intValue) / 1000)
            }
            return Date(timeIntervalSince1970: TimeInterval(intValue))
        }

        if let date = iso8601Fractional.date(from: value) ?? iso8601.date(from: value) {
            return date
        }

        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        if value.count == 14, value.allSatisfy(\.isNumber) {
            let head = String(value.prefix(14))
            for formatter in formatters where formatter.dateFormat == "yyyyMMddHHmmss" {
                if let date = formatter.date(from: head) {
                    return date
                }
            }
        }

        if value.count <= 8, value.contains(":") {
            let today = dayFormatter.string(from: Date())
            value = "\(today) \(value)"
            for formatter in formatters where formatter.dateFormat == "yyyy-MM-dd HH:mm:ss" {
                if let date = formatter.date(from: value) {
                    return date
                }
            }
        }

        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
