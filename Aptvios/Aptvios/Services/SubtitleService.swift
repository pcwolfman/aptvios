import Foundation

struct SubtitleResult: Identifiable, Hashable {
    let id: String
    let title: String
    let language: String
    let downloadURL: String?
    let source: String
}

actor SubtitleService {
    static let shared = SubtitleService()

    /// OpenSubtitles.com API (kullanıcı kendi API key'ini Ayarlar'dan girer).
    func searchOpenSubtitles(query: String, apiKey: String) async throws -> [SubtitleResult] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AptviosError.parseFailed("OpenSubtitles API key gerekli")
        }
        guard var components = URLComponents(string: "https://api.opensubtitles.com/api/v1/subtitles") else {
            throw AptviosError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "languages", value: "tr,en")
        ]
        guard let url = components.url else { throw AptviosError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("Aptvios v1.2", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AptviosError.downloadFailed("OpenSubtitles HTTP \(http.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            return []
        }

        return list.prefix(30).compactMap { item in
            guard let attrs = item["attributes"] as? [String: Any] else { return nil }
            let id = (item["id"] as? String) ?? UUID().uuidString
            let title = (attrs["release"] as? String)
                ?? (attrs["feature_details"] as? [String: Any])?["title"] as? String
                ?? query
            let language = (attrs["language"] as? String) ?? "?"
            let files = attrs["files"] as? [[String: Any]]
            let fileId = files?.first?["file_id"]
            return SubtitleResult(
                id: id,
                title: title,
                language: language,
                downloadURL: fileId.map { "opensubtitles-file:\($0)" },
                source: "OpenSubtitles"
            )
        }
    }

    /// assrt.net (ücretsiz arama; token opsiyonel).
    func searchAssrt(query: String, token: String?) async throws -> [SubtitleResult] {
        var components = URLComponents(string: "http://api.assrt.net/v1/sub/search")!
        var items = [URLQueryItem(name: "q", value: query)]
        if let token, !token.isEmpty {
            items.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = items
        guard let url = components.url else { throw AptviosError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AptviosError.downloadFailed("assrt HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["sub"] as? [[String: Any]] else { return [] }

        return list.prefix(30).compactMap { item in
            let id = String(describing: item["id"] ?? UUID().uuidString)
            let title = (item["native_name"] as? String) ?? (item["videoname"] as? String) ?? query
            let url = item["url"] as? String
            return SubtitleResult(
                id: id,
                title: title,
                language: "zh/en",
                downloadURL: url,
                source: "assrt"
            )
        }
    }
}
