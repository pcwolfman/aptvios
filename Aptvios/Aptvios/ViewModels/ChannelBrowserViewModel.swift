import Foundation
import Combine

@MainActor
final class ChannelBrowserViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedGroup: String? = nil
    @Published private(set) var allChannels: [PlayableChannel] = []
    @Published private(set) var groups: [String] = []

    private var persistence: PersistenceController { .shared }

    var filteredChannels: [PlayableChannel] {
        var list = allChannels
        if let selectedGroup {
            list = list.filter { $0.groupTitle == selectedGroup }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(q)
                    || $0.groupTitle.localizedCaseInsensitiveContains(q)
                    || ($0.tvgId?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        return list
    }

    func reload() {
        allChannels = persistence.allEnabledChannels()
        let counts = Dictionary(grouping: allChannels, by: \.groupTitle).mapValues(\.count)
        groups = counts.keys.sorted { a, b in
            if a == "Uncategorized" { return false }
            if b == "Uncategorized" { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    func groupCount(_ group: String) -> Int {
        allChannels.filter { $0.groupTitle == group }.count
    }
}
