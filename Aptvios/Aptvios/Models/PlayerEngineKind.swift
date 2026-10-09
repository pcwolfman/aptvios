import Foundation

enum PlayerEngineKind: String, CaseIterable, Identifiable {
    case avPlayer
    case ksPlayer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .avPlayer: return "AVPlayer (sistem)"
        case .ksPlayer: return "KSPlayer (FFmpeg)"
        }
    }

    var subtitle: String {
        switch self {
        case .avPlayer: return "HLS / MP4 için hızlı ve stabil"
        case .ksPlayer: return "MPEG-TS ve daha fazla codec"
        }
    }

    static var isKSPlayerLinked: Bool {
        #if canImport(KSPlayer)
        true
        #else
        false
        #endif
    }
}
