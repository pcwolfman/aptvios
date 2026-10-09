import AVFoundation
import MediaPlayer
import CarPlay
import UIKit

/// CarPlay ve kilit ekranı için ortak oynatma denetleyicisi.
@MainActor
final class CarPlayPlaybackController: NSObject {
    static let shared = CarPlayPlaybackController()

    let player = AVPlayer()

    private(set) var queue: [PlayableChannel] = []
    private(set) var current: PlayableChannel?
    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?

    var onChannelChanged: ((PlayableChannel) -> Void)?

    private override init() {
        super.init()
        configureAudioSession()
        configureRemoteCommands()
        addPeriodicObserver()
    }

    func play(_ channel: PlayableChannel, in list: [PlayableChannel] = []) {
        queue = list.isEmpty ? [channel] : list
        current = channel
        load(channel)
        PersistenceController.shared.recordPlay(channel)
        onChannelChanged?(channel)
    }

    func playNext() {
        guard let current,
              let idx = queue.firstIndex(where: { $0.url == current.url }),
              idx + 1 < queue.count else { return }
        play(queue[idx + 1], in: queue)
    }

    func playPrevious() {
        guard let current,
              let idx = queue.firstIndex(where: { $0.url == current.url }),
              idx > 0 else { return }
        play(queue[idx - 1], in: queue)
    }

    func togglePlayPause() {
        if player.rate > 0 {
            player.pause()
        } else {
            player.play()
        }
        refreshNowPlayingPlayback()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func load(_ channel: PlayableChannel) {
        guard let url = URL(string: channel.url) else { return }

        var headers: [String: String] = [
            "User-Agent": AppSettings.shared.userAgent
        ]
        if let ua = channel.userAgent { headers["User-Agent"] = ua }
        if let ref = channel.referer { headers["Referer"] = ref }

        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                if item.status == .failed {
                    self?.updateNowPlaying(error: item.error?.localizedDescription)
                } else if item.status == .readyToPlay {
                    self?.updateNowPlaying()
                }
            }
        }

        player.replaceCurrentItem(with: item)
        player.play()
        updateNowPlaying()
    }

    private func updateNowPlaying(error: String? = nil) {
        guard let channel = current else { return }
        let epg = EPGService.shared.nowAndNext(for: channel.tvgId)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: channel.name,
            MPMediaItemPropertyAlbumTitle: channel.groupTitle,
            MPMediaItemPropertyArtist: epg.now?.title ?? channel.sourceName ?? "Aptvios",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate > 0 ? 1.0 : 0.0
        ]

        if let next = epg.next {
            info[MPMediaItemPropertyComments] = "Sonraki: \(next.title)"
        }
        if let error {
            info[MPMediaItemPropertyAlbumTitle] = error
        }

        if let logo = channel.logo, let logoURL = URL(string: logo) {
            Task {
                if let image = await Self.loadArtwork(from: logoURL) {
                    var copy = info
                    copy[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = copy
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func refreshNowPlayingPlayback() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate > 0 ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            self?.player.play()
            Task { @MainActor in self?.refreshNowPlayingPlayback() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause()
            Task { @MainActor in self?.refreshNowPlayingPlayback() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
    }

    private func addPeriodicObserver() {
        let interval = CMTime(seconds: 5, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.refreshNowPlayingPlayback()
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("CarPlay audio session error: \(error)")
        }
    }

    private static func loadArtwork(from url: URL) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
