import Foundation
import Combine

/// Persists bookmarks across launches, using the original pin storage key so
/// previously pinned documents and guides remain saved. Additional resource
/// kinds use namespaced keys supplied by BookmarkKey.
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
