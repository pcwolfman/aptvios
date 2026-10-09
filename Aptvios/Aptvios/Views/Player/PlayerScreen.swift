import SwiftUI
import AVKit

struct PlayerScreen: View {
    let channel: PlayableChannel

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playerRouter: PlayerRouter
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var persistence: PersistenceController
    @EnvironmentObject private var epg: EPGService

    @StateObject private var vm = PlayerViewModel()
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var ksPlaying = true
    @State private var ksBuffering = true
    @State private var ksError: String?

    private var useKSPlayer: Bool {
        settings.playerEngine == .ksPlayer
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            playerLayer
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }

            if isBuffering {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }

            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }

            if let error = displayError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Button("Tekrar dene") { reloadActive() }
                        .buttonStyle(.borderedProminent)
                    if useKSPlayer {
                        Button("AVPlayer’a geç") {
                            settings.playerEngine = .avPlayer
                            reloadActive()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            persistence.recordPlay(channel)
            if settings.rememberLastChannel {
                settings.lastChannelURL = channel.url
            }
            reloadActive()
            scheduleHide()
        }
        .onChange(of: playerRouter.activeChannel) { _, newValue in
            guard newValue != nil else { return }
            reloadActive()
            showControls = true
            scheduleHide()
        }
        .onChange(of: settings.playerEngine) { _, _ in
            reloadActive()
        }
        .onDisappear {
            vm.stop()
            hideTask?.cancel()
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < -60 {
                        playerRouter.playNext()
                    } else if value.translation.width > 60 {
                        playerRouter.playPrevious()
                    } else if value.translation.height > 80 {
                        playerRouter.dismiss()
                        dismiss()
                    }
                }
        )
    }

    @ViewBuilder
    private var playerLayer: some View {
        if useKSPlayer, let url = URL(string: active.url) {
            KSPlayerContainer(
                url: url,
                userAgent: active.userAgent ?? settings.userAgent,
                referer: active.referer,
                isPlaying: $ksPlaying,
                isBuffering: $ksBuffering,
                errorMessage: $ksError
            )
            .id(active.url + "-ks")
        } else {
            VideoPlayerView(player: vm.player)
                .id(active.url + "-av")
        }
    }

    private var active: PlayableChannel {
        playerRouter.activeChannel ?? channel
    }

    private var isPlaying: Bool {
        useKSPlayer ? ksPlaying : vm.isPlaying
    }

    private var isBuffering: Bool {
        useKSPlayer ? ksBuffering : vm.isBuffering
    }

    private var displayError: String? {
        useKSPlayer ? ksError : vm.errorMessage
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    playerRouter.dismiss()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.35), in: Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(active.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let now = epg.nowAndNext(for: active.tvgId).now {
                            Text(now.title)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        } else {
                            Text(active.groupTitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Text(useKSPlayer ? "KS" : "AV")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.2), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }

                Spacer()

                Button {
                    persistence.toggleFavorite(active)
                } label: {
                    Image(systemName: persistence.isFavorite(url: active.url) ? "star.fill" : "star")
                        .foregroundStyle(persistence.isFavorite(url: active.url) ? .yellow : .white)
                        .padding(10)
                        .background(.black.opacity(0.35), in: Circle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            HStack(spacing: 36) {
                Button { playerRouter.playPrevious() } label: {
                    Image(systemName: "backward.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }

                Button { togglePlay() } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                }

                Button { playerRouter.playNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            .padding(.bottom, 12)

            if !useKSPlayer, !vm.isLive, vm.duration > 0 {
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { vm.position },
                            set: { vm.seek(to: $0) }
                        ),
                        in: 0...max(vm.duration, 1)
                    )
                    .tint(.white)

                    HStack {
                        Text(formatTime(vm.position))
                        Spacer()
                        Text(formatTime(vm.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            } else {
                Text("CANLI")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 28)
            }
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.65), .clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private func reloadActive() {
        if settings.externalPlayer != .system {
            _ = settings.externalPlayer.open(streamURL: active.url)
            return
        }
        ksError = nil
        vm.errorMessage = nil
        if useKSPlayer {
            vm.stop()
            ksBuffering = true
            ksPlaying = true
        } else {
            ksPlaying = false
            vm.load(active, userAgent: settings.userAgent)
        }
    }

    private func togglePlay() {
        if useKSPlayer {
            ksPlaying.toggle()
        } else {
            vm.togglePlay()
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite else { return "00:00" }
        let total = Int(value)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
