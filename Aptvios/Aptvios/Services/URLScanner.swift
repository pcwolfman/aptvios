import Foundation

/// APTV tarzı yedek tarama: `http://ip/path(0-9)/index.m3u8` kalıbını dener.
enum URLScanner {
    static func expandPattern(_ pattern: String) -> [String] {
        if let range = pattern.range(of: #"(0-9)"#) {
            return (0...9).map { pattern.replacingCharacters(in: range, with: String($0)) }
        }
        if let range = pattern.range(of: #"(0-f)"#) {
            let hex = Array("0123456789abcdef")
            return hex.map { pattern.replacingCharacters(in: range, with: String($0)) }
        }
        return [pattern]
    }

    static func probe(
        pattern: String,
        userAgent: String,
        timeout: TimeInterval = 8
    ) async -> [String] {
        let candidates = expandPattern(pattern)
        var working: [String] = []

        await withTaskGroup(of: (String, Bool).self) { group in
            for urlString in candidates {
                group.addTask {
                    let ok = await isReachable(urlString, userAgent: userAgent, timeout: timeout)
                    return (urlString, ok)
                }
            }
            for await (url, ok) in group {
                if ok { working.append(url) }
            }
        }

        return working.sorted()
    }

    private static func isReachable(
        _ urlString: String,
        userAgent: String,
        timeout: TimeInterval
    ) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")

        do {
            let session = URLSession(configuration: ProxySession.shared.configuration)
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...399).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
