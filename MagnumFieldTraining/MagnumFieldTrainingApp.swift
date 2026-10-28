import SwiftUI

@main
struct MagnumFieldTrainingApp: App {
    @StateObject private var pinnedStore = PinnedStore()
    @StateObject private var catalogStore = CatalogStore()
    @StateObject private var seenStore = SeenStore.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared

    var body: some Scene {
        WindowGroup {
            AppLockView()
                .environmentObject(pinnedStore)
                .environmentObject(catalogStore)
                .environmentObject(seenStore)
                .environmentObject(networkMonitor)
                .modifier(AppLanguageModifier())
        }
    }
}
