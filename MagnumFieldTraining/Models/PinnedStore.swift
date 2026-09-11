import Foundation
import Combine

/// Persists which walkthroughs a foreman has manually pinned, keyed by each
/// document's stable `persistenceKey`. Pinned items show in the "Pinned"
/// section on the home screen -- this replaces automatic "Recently Viewed"
/// tracking with something the foreman controls directly, tapping a pin
/// icon next to any PDF or video. Backed by UserDefaults so pins survive
/// relaunches without needing any network connection.
final class PinnedStore: ObservableObject {
    @Published private(set) var pinnedKeys: Set<String>

    private let defaultsKey = "MagnumFieldTraining.pinnedKeys"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.array(forKey: defaultsKey) as? [String] ?? []
        self.pinnedKeys = Set(saved)
    }

    func isPinned(_ key: String) -> Bool {
        pinnedKeys.contains(key)
    }

    func toggle(_ key: String) {
        if pinnedKeys.contains(key) {
            pinnedKeys.remove(key)
        } else {
            pinnedKeys.insert(key)
        }
        defaults.set(Array(pinnedKeys), forKey: defaultsKey)
    }
}
