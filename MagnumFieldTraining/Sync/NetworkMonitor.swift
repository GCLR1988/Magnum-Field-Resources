import Foundation
import Network
import Combine
import os

/// Tracks whether the device currently has a Wi-Fi connection, so video
/// downloads can be gated to Wi-Fi only when the user prefers that (see
/// SettingsStore), and whether it has any network connection at all, so the
/// UI can show an offline banner. `isConnected` is only written on the main
/// thread since it's read by SwiftUI; `isOnWiFi` is also read from off-main
/// contexts (the MediaCache actor deciding whether a video may download),
/// so it's guarded by a lock instead of relying on main-thread-only access.
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.magnumfieldtraining.networkmonitor")

    /// Starts false (not true) so the brief window before the first path update
    /// arrives can't mistake a cellular connection for Wi-Fi and let a video
    /// download slip through the Wi-Fi-only setting.
    private let wifiState = OSAllocatedUnfairLock(initialState: false)

    var isOnWiFi: Bool {
        wifiState.withLock { $0 }
    }

    @Published private(set) var isConnected = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.wifiState.withLock { $0 = path.usesInterfaceType(.wifi) }
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                self.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }
}
