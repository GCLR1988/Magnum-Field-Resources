import Foundation
import Network
import Combine

/// Tracks whether the device currently has a Wi-Fi connection, so video
/// downloads can be gated to Wi-Fi only when the user prefers that (see
/// SettingsStore), and whether it has any network connection at all, so the
/// UI can show an offline banner. Both properties are only ever written on
/// the main thread, so they're safe to read from any main-actor context
/// (which is where every call site in this app lives).
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.magnumfieldtraining.networkmonitor")

    private(set) var isOnWiFi = true
    @Published private(set) var isConnected = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let onWiFi = path.usesInterfaceType(.wifi)
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isOnWiFi = onWiFi
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }
}
