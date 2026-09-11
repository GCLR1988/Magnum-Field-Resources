import Foundation
import Combine

/// Tracks which walkthroughs a foreman has already viewed or had listed in
/// front of them, so newly-synced files can be flagged with a "New" badge
/// until they're noticed. Backed by UserDefaults so it survives relaunches.
final class SeenStore: ObservableObject {
    static let shared = SeenStore()

    @Published private(set) var seenKeys: Set<String>
    /// Whether the one-time baseline seed (see `seedIfNeeded`) has completed.
    /// `isNew` treats everything as "not new" until this is true, so that on
    /// a fresh install, walkthroughs from a program that finishes syncing
    /// early don't flash a "New" badge just because other programs are
    /// still syncing and the baseline hasn't been established yet.
    @Published private(set) var hasSeeded: Bool

    private let defaultsKey = "MagnumFieldTraining.seenKeys"
    private let hasSeededKey = "MagnumFieldTraining.seenStoreSeeded"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.array(forKey: defaultsKey) as? [String] ?? []
        self.seenKeys = Set(saved)
        self.hasSeeded = defaults.bool(forKey: hasSeededKey)
    }

    func isNew(_ key: String) -> Bool {
        hasSeeded && !seenKeys.contains(key)
    }

    /// Marks the given keys as seen. Only writes to disk if something actually changed.
    func markSeen(_ keys: [String]) {
        let unseen = keys.filter { !seenKeys.contains($0) }
        guard !unseen.isEmpty else { return }
        seenKeys.formUnion(unseen)
        defaults.set(Array(seenKeys), forKey: defaultsKey)
    }

    /// Marks every currently-known file as seen, but only the very first time
    /// this is ever called. Without this, a fresh install would show every
    /// existing walkthrough as "New" the first time programs sync, since none
    /// of them would be in `seenKeys` yet -- this seeds a baseline so "New"
    /// only ever means "appeared after you started using the app."
    func seedIfNeeded(_ keys: [String]) {
        guard !hasSeeded else { return }
        seenKeys.formUnion(keys)
        defaults.set(Array(seenKeys), forKey: defaultsKey)
        defaults.set(true, forKey: hasSeededKey)
        hasSeeded = true
    }
}
