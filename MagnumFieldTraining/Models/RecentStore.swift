import Foundation
import Observation

/// Stores only stable identifiers; current titles and destinations come from the library.
@MainActor
@Observable
final class RecentStore {
    static let shared = RecentStore()
    private(set) var keys: [String]
    private let defaults: UserDefaults
    private let storageKey = "MagnumFieldTraining.recentGuideKeys"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keys = defaults.stringArray(forKey: storageKey) ?? []
    }

    func record(_ key: String) {
        keys.removeAll { $0 == key }
        keys.insert(key, at: 0)
        keys = Array(keys.prefix(20))
        defaults.set(keys, forKey: storageKey)
    }

    func clear() {
        keys = []
        defaults.removeObject(forKey: storageKey)
    }
}
