import UIKit

enum ExternalPlayer: String, CaseIterable, Identifiable {
    case system
    case vlc
    case infuse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Aptvios (içeride)"
        case .vlc: return "VLC"
        case .infuse: return "Infuse"
        }
    }

    func open(streamURL: String) -> Bool {
        switch self {
        case .system:
            return false
        case .vlc:
            // vlc-x-callback://x-callback-url/stream?url=
            guard let encoded = streamURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "vlc-x-callback://x-callback-url/stream?url=\(encoded)") else { return false }
            return openURL(url)
        case .infuse:
            guard let encoded = streamURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "infuse://x-callback-url/play?url=\(encoded)") else { return false }
            return openURL(url)
        }
    }

    private func openURL(_ url: URL) -> Bool {
        guard UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}
