import Foundation
import Network

/// Yerel ağda playlist URL paylaşımı (_aptvios._tcp / APTV uyumlu _aptv._tcp dinleme).
@MainActor
final class BonjourSyncService: ObservableObject {
    static let shared = BonjourSyncService()

    @Published private(set) var discovered: [BonjourPeer] = []
    @Published var isAdvertising = false
    @Published var lastError: String?

    private var browser: NWBrowser?
    private var listener: NWListener?
    private var sharedPlaylistURL: String = ""

    struct BonjourPeer: Identifiable, Hashable {
        let id: String
        let name: String
        let playlistURL: String?
    }

    func startAdvertising(playlistURL: String, name: String = "Aptvios") {
        stopAdvertising()
        sharedPlaylistURL = playlistURL
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            listener = try NWListener(using: params)
            listener?.service = NWListener.Service(name: name, type: "_aptvios._tcp")
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleIncoming(connection)
                }
            }
            listener?.start(queue: .main)
            isAdvertising = true
        } catch {
            lastError = error.localizedDescription
            isAdvertising = false
        }
    }

    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
    }

    func startBrowsing() {
        stopBrowsing()
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_aptvios._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.discovered = results.compactMap { result in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return BonjourPeer(id: name, name: name, playlistURL: nil)
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        discovered = []
    }

    private func handleIncoming(_ connection: NWConnection) {
        connection.start(queue: .main)
        let payload = (sharedPlaylistURL + "\n").data(using: .utf8) ?? Data()
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
