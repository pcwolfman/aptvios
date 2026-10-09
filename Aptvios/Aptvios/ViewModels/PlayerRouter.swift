import Foundation
import Combine

@MainActor
final class PlayerRouter: ObservableObject {
    @Published var activeChannel: PlayableChannel?
    @Published var playlist: [PlayableChannel] = []

    func play(_ channel: PlayableChannel, in list: [PlayableChannel] = []) {
        playlist = list.isEmpty ? [channel] : list
        activeChannel = channel
    }

    func playNext() {
        guard let current = activeChannel,
              let idx = playlist.firstIndex(of: current),
              idx + 1 < playlist.count else { return }
        activeChannel = playlist[idx + 1]
    }

    func playPrevious() {
        guard let current = activeChannel,
              let idx = playlist.firstIndex(of: current),
              idx > 0 else { return }
        activeChannel = playlist[idx - 1]
    }

    func dismiss() {
        activeChannel = nil
    }
}
