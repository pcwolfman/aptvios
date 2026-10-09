import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var errorMessage: String?
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var isLive = true

    let player = AVPlayer()
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var statusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var keepUpObservation: NSKeyValueObservation?

    init() {
        configureAudioSession()
        addPeriodicObserver()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func load(_ channel: PlayableChannel, userAgent: String) {
        errorMessage = nil
        isBuffering = true

        guard let url = URL(string: channel.url) else {
            errorMessage = "Geçersiz yayın URL'si"
            isBuffering = false
            return
        }

        var headers: [String: String] = [
            "User-Agent": channel.userAgent ?? userAgent
        ]
        if let referer = channel.referer, !referer.isEmpty {
            headers["Referer"] = referer
        }

        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        observe(item: item)
        player.play()
        isPlaying = true
        updateNowPlaying(channel)
    }

    func togglePlay() {
        if player.rate > 0 {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        clearNowPlaying()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time)
    }

    private func observe(item: AVPlayerItem) {
        itemStatusObservation?.invalidate()
        bufferEmptyObservation?.invalidate()
        keepUpObservation?.invalidate()

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.isBuffering = false
                    self?.errorMessage = nil
                    let d = item.duration.seconds
                    if d.isFinite && d > 0 {
                        self?.duration = d
                        self?.isLive = false
                    } else {
                        self?.isLive = true
                        self?.duration = 0
                    }
                case .failed:
                    self?.isBuffering = false
                    self?.errorMessage = item.error?.localizedDescription ?? "Oynatma hatası"
                default:
                    break
                }
            }
        }

        bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                if item.isPlaybackBufferEmpty { self?.isBuffering = true }
            }
        }

        keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                if item.isPlaybackLikelyToKeepUp { self?.isBuffering = false }
            }
        }
    }

    private func addPeriodicObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.position = time.seconds.isFinite ? time.seconds : 0
            if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
                self.isLive = false
            }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            let homePod = UserDefaults.standard.bool(forKey: "settings.homePodMode")
            let mode: AVAudioSession.Mode = homePod ? .spokenAudio : .moviePlayback
            try session.setCategory(.playback, mode: mode, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func updateNowPlaying(_ channel: PlayableChannel) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: channel.name,
            MPMediaItemPropertyAlbumTitle: channel.groupTitle
        ]
        if let source = channel.sourceName {
            info[MPMediaItemPropertyArtist] = source
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            self?.player.play()
            Task { @MainActor in self?.isPlaying = true }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause()
            Task { @MainActor in self?.isPlaying = false }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
