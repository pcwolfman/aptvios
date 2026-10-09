import Foundation

enum SourceKind: String, CaseIterable, Identifiable, Codable {
    case m3u
    case txt
    case xtream
    case stalker
    case single
    case blank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .m3u: return "M3U Playlist"
        case .txt: return "TXT Liste"
        case .xtream: return "Xtream Codes"
        case .stalker: return "Stalker Portal"
        case .single: return "Tek Kanal"
        case .blank: return "Boş Kaynak"
        }
    }
}
