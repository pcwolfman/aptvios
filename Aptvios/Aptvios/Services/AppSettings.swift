import Foundation
import Combine
import UIKit

enum EPGMode: String, CaseIterable, Identifiable {
    case xmltv
    case diyp

    var id: String { rawValue }
    var title: String {
        switch self {
        case .xmltv: return "XMLTV"
        case .diyp: return "DIYP"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let defaultUserAgent = "Aptvios/1.2 (iOS; IPTV Player)"
    static let defaultEPG = "https://epg.aptv.app/pp.xml.gz"

    @Published var epgURL: String {
        didSet { defaults.set(epgURL, forKey: Keys.epgURL) }
    }

    @Published var epgMode: EPGMode {
        didSet { defaults.set(epgMode.rawValue, forKey: Keys.epgMode) }
    }

    @Published var userAgent: String {
        didSet { defaults.set(userAgent, forKey: Keys.userAgent) }
    }

    @Published var forceDarkMode: Bool {
        didSet { defaults.set(forceDarkMode, forKey: Keys.forceDarkMode) }
    }

    @Published var autoPlay: Bool {
        didSet { defaults.set(autoPlay, forKey: Keys.autoPlay) }
    }

    @Published var showChannelLogos: Bool {
        didSet { defaults.set(showChannelLogos, forKey: Keys.showLogos) }
    }

    @Published var rememberLastChannel: Bool {
        didSet { defaults.set(rememberLastChannel, forKey: Keys.rememberLast) }
    }

    @Published var gridColumns: Int {
        didSet { defaults.set(gridColumns, forKey: Keys.gridColumns) }
    }

    @Published var playerEngine: PlayerEngineKind {
        didSet { defaults.set(playerEngine.rawValue, forKey: Keys.playerEngine) }
    }

    @Published var externalPlayer: ExternalPlayer {
        didSet { defaults.set(externalPlayer.rawValue, forKey: Keys.externalPlayer) }
    }

    @Published var iCloudSync: Bool {
        didSet { defaults.set(iCloudSync, forKey: Keys.iCloudSync) }
    }

    @Published var backgroundPlayback: Bool {
        didSet { defaults.set(backgroundPlayback, forKey: Keys.backgroundPlayback) }
    }

    @Published var showPreviews: Bool {
        didSet { defaults.set(showPreviews, forKey: Keys.showPreviews) }
    }

    @Published var openSubtitlesAPIKey: String {
        didSet { defaults.set(openSubtitlesAPIKey, forKey: Keys.openSubtitlesAPIKey) }
    }

    @Published var assrtToken: String {
        didSet { defaults.set(assrtToken, forKey: Keys.assrtToken) }
    }

    @Published var homePodMode: Bool {
        didSet { defaults.set(homePodMode, forKey: Keys.homePodMode) }
    }

    @Published var alternateIconName: String? {
        didSet {
            defaults.set(alternateIconName, forKey: Keys.alternateIcon)
            applyAlternateIcon()
        }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let epgURL = "settings.epgURL"
        static let epgMode = "settings.epgMode"
        static let userAgent = "settings.userAgent"
        static let forceDarkMode = "settings.forceDarkMode"
        static let autoPlay = "settings.autoPlay"
        static let showLogos = "settings.showLogos"
        static let rememberLast = "settings.rememberLast"
        static let gridColumns = "settings.gridColumns"
        static let lastChannelURL = "settings.lastChannelURL"
        static let playerEngine = "settings.playerEngine"
        static let externalPlayer = "settings.externalPlayer"
        static let iCloudSync = "settings.iCloudSync"
        static let backgroundPlayback = "settings.backgroundPlayback"
        static let showPreviews = "settings.showPreviews"
        static let openSubtitlesAPIKey = "settings.openSubtitlesAPIKey"
        static let assrtToken = "settings.assrtToken"
        static let homePodMode = "settings.homePodMode"
        static let alternateIcon = "settings.alternateIcon"
    }

    init() {
        epgURL = defaults.string(forKey: Keys.epgURL) ?? Self.defaultEPG
        if let raw = defaults.string(forKey: Keys.epgMode), let mode = EPGMode(rawValue: raw) {
            epgMode = mode
        } else {
            epgMode = .xmltv
        }
        userAgent = defaults.string(forKey: Keys.userAgent) ?? Self.defaultUserAgent
        forceDarkMode = defaults.object(forKey: Keys.forceDarkMode) as? Bool ?? true
        autoPlay = defaults.object(forKey: Keys.autoPlay) as? Bool ?? true
        showChannelLogos = defaults.object(forKey: Keys.showLogos) as? Bool ?? true
        rememberLastChannel = defaults.object(forKey: Keys.rememberLast) as? Bool ?? true
        gridColumns = defaults.object(forKey: Keys.gridColumns) as? Int ?? 1
        if let raw = defaults.string(forKey: Keys.playerEngine),
           let engine = PlayerEngineKind(rawValue: raw) {
            playerEngine = engine
        } else {
            playerEngine = .avPlayer
        }
        if let raw = defaults.string(forKey: Keys.externalPlayer),
           let player = ExternalPlayer(rawValue: raw) {
            externalPlayer = player
        } else {
            externalPlayer = .system
        }
        iCloudSync = defaults.object(forKey: Keys.iCloudSync) as? Bool ?? false
        backgroundPlayback = defaults.object(forKey: Keys.backgroundPlayback) as? Bool ?? true
        showPreviews = defaults.object(forKey: Keys.showPreviews) as? Bool ?? false
        openSubtitlesAPIKey = defaults.string(forKey: Keys.openSubtitlesAPIKey) ?? ""
        assrtToken = defaults.string(forKey: Keys.assrtToken) ?? ""
        homePodMode = defaults.object(forKey: Keys.homePodMode) as? Bool ?? false
        alternateIconName = defaults.string(forKey: Keys.alternateIcon)
    }

    var lastChannelURL: String? {
        get { defaults.string(forKey: Keys.lastChannelURL) }
        set { defaults.set(newValue, forKey: Keys.lastChannelURL) }
    }

    private func applyAlternateIcon() {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let name = alternateIconName
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                print("Alternate icon error: \(error)")
            }
        }
    }
}
