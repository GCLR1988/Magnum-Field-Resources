import Foundation
import Combine

/// Lightweight, persisted user preferences for the app.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private static let wifiOnlyKey = "MagnumFieldTraining.wifiOnlyForVideos"

    /// When true (the default), videos only auto-download over Wi-Fi so a
    /// foreman's cellular data isn't eaten by background syncing. PDFs are
    /// small enough that they always download regardless of this setting.
    @Published var wifiOnlyForVideos: Bool {
        didSet {
            UserDefaults.standard.set(wifiOnlyForVideos, forKey: Self.wifiOnlyKey)
        }
    }

    private init() {
        if UserDefaults.standard.object(forKey: Self.wifiOnlyKey) == nil {
            wifiOnlyForVideos = true
        } else {
            wifiOnlyForVideos = UserDefaults.standard.bool(forKey: Self.wifiOnlyKey)
        }
    }
}
