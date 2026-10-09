import SwiftUI
import AVKit

struct SplitScreenPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var persistence: PersistenceController

    @State private var left: PlayableChannel?
    @State private var right: PlayableChannel?
    @StateObject private var leftVM = PlayerViewModel()
    @StateObject private var rightVM = PlayerViewModel()
    @State private var pickSide: Side = .left
    @State private var showPicker = false

    private enum Side { case left, right }

    private var catalog: [PlayableChannel] {
        persistence.allEnabledChannels()
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let vertical = geo.size.height > geo.size.width
                Group {
                    if vertical {
                        VStack(spacing: 2) {
                            pane(channel: left, vm: leftVM, side: .left)
                            pane(channel: right, vm: rightVM, side: .right)
                        }
                    } else {
                        HStack(spacing: 2) {
                            pane(channel: left, vm: leftVM, side: .left)
                            pane(channel: right, vm: rightVM, side: .right)
                        }
                    }
                }
                .background(Color.black)
            }
            .navigationTitle("Çoklu Ekran")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        leftVM.stop()
                        rightVM.stop()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                NavigationStack {
                    List(catalog) { channel in
                        Button {
                            assign(channel)
                            showPicker = false
                        } label: {
                            Text(channel.name)
                        }
                    }
                    .navigationTitle(pickSide == .left ? "Sol / Üst" : "Sağ / Alt")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Kapat") { showPicker = false }
                        }
                    }
                }
            }
            .onDisappear {
                leftVM.stop()
                rightVM.stop()
            }
        }
    }

    private func pane(channel: PlayableChannel?, vm: PlayerViewModel, side: Side) -> some View {
        ZStack {
            Color.black
            if channel != nil {
                VideoPlayerView(player: vm.player)
            } else {
                Button {
                    pickSide = side
                    showPicker = true
                } label: {
                    Label("Kanal seç", systemImage: "plus.rectangle.on.rectangle")
                        .foregroundStyle(.white)
                }
            }

            VStack {
                HStack {
                    Text(channel?.name ?? "Boş")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.45), in: Capsule())
                    Spacer()
                    Button {
                        pickSide = side
                        showPicker = true
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                }
                .padding(8)
                Spacer()
            }
        }
    }

    private func assign(_ channel: PlayableChannel) {
        persistence.recordPlay(channel)
        switch pickSide {
        case .left:
            left = channel
            leftVM.load(channel, userAgent: settings.userAgent)
        case .right:
            right = channel
            rightVM.load(channel, userAgent: settings.userAgent)
        }
    }
}
