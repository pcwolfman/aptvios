import SwiftUI

#if canImport(KSPlayer)
import KSPlayer

struct KSPlayerContainer: View {
    let url: URL
    var userAgent: String?
    var referer: String?
    @Binding var isPlaying: Bool
    @Binding var isBuffering: Bool
    @Binding var errorMessage: String?

    var body: some View {
        KSVideoPlayerView(url: url, options: makeOptions())
            .onAppear {
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
                isBuffering = false
                isPlaying = true
                errorMessage = nil
            }
    }

    private func makeOptions() -> KSOptions {
        KSOptions.isAutoPlay = true
        let options = KSOptions()
        options.userAgent = userAgent
        options.referer = referer
        options.canStartPictureInPictureAutomaticallyFromInline = true
        return options
    }
}

#else

struct KSPlayerContainer: View {
    let url: URL
    var userAgent: String? = nil
    var referer: String? = nil
    @Binding var isPlaying: Bool
    @Binding var isBuffering: Bool
    @Binding var errorMessage: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("KSPlayer henüz çözümlenmedi")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Mac’te Xcode açılınca paket otomatik iner. Ayarlar → Oynatıcı motoru → KSPlayer.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            isBuffering = false
            isPlaying = false
            errorMessage = "KSPlayer paketi bekleniyor; şimdilik AVPlayer kullanın"
        }
    }
}

#endif
