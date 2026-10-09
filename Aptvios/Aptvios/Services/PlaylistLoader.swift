import Foundation

actor PlaylistLoader {
    static let shared = PlaylistLoader()

    func download(urlString: String, userAgent: String?) async throws -> String {
        guard let url = URL(string: urlString), url.scheme != nil else {
            throw AptviosError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(userAgent ?? AppSettings.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain,*/*", forHTTPHeaderField: "Accept")

        do {
            let session = URLSession(configuration: ProxySession.shared.configuration)
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw AptviosError.downloadFailed("HTTP \(http.statusCode)")
            }
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? String(data: data, encoding: .ascii) else {
                throw AptviosError.parseFailed("Metin kodlaması okunamadı")
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AptviosError.emptyPlaylist
            }
            return text
        } catch let error as AptviosError {
            throw error
        } catch {
            throw AptviosError.downloadFailed(error.localizedDescription)
        }
    }

    func loadChannels(
        urlString: String?,
        rawContent: String?,
        format: PlaylistFormat,
        userAgent: String?
    ) async throws -> (text: String, channels: [ParsedChannel]) {
        let text: String
        if let rawContent, !rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = rawContent
        } else if let urlString, !urlString.isEmpty {
            text = try await download(urlString: urlString, userAgent: userAgent)
        } else {
            throw AptviosError.invalidURL
        }

        let channels = try PlaylistParser.parse(text, format: format)
        return (text, channels)
    }
}
