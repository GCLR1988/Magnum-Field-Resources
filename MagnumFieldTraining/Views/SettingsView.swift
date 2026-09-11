import SwiftUI

/// Settings screen: the Wi-Fi-only-for-videos toggle, plus a Storage section
/// for seeing how much space downloaded PDFs and videos are using and
/// clearing them if a foreman's device is running low.
struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @EnvironmentObject private var catalogStore: CatalogStore
    @State private var showClearCacheConfirm = false
    @State private var cacheVersion = UUID()

    var body: some View {
        Form {
            Section {
                Toggle("Wi-Fi Only for Videos", isOn: $settingsStore.wifiOnlyForVideos)
            } header: {
                Text("Data Usage")
            } footer: {
                Text("Videos only auto-download over Wi-Fi to protect your cellular data. PDFs are small and always download automatically. Turn this off to allow videos to download over cellular too, or use \"Download Anyway\" when viewing a single video in the field.")
            }

            Section {
                ForEach(dropboxPrograms) { program in
                    HStack {
                        Text(program.name)
                        Spacer()
                        Text(Self.byteFormatter.string(fromByteCount: cachedSize(for: program)))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Total")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(Self.byteFormatter.string(fromByteCount: totalCachedSize))
                        .foregroundStyle(.secondary)
                }
                Button("Clear Cached Files", role: .destructive) {
                    showClearCacheConfirm = true
                }
                .disabled(totalCachedSize == 0)
            } header: {
                Text("Storage")
            } footer: {
                Text("Downloaded PDFs and videos are kept on this device so they're available in the field without a signal. Clearing them frees up space; files re-download automatically the next time you open them.")
            }
            .id(cacheVersion)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color("WarmBackground"))
        .confirmationDialog(
            "Clear all cached PDFs and videos?",
            isPresented: $showClearCacheConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Cached Files", role: .destructive) {
                Task {
                    await MediaCache.shared.clearAll()
                    cacheVersion = UUID()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need a connection to re-download them before viewing.")
        }
    }

    private var dropboxPrograms: [Program] {
        catalogStore.programs.filter {
            if case .dropbox = $0.source { return true }
            return false
        }
    }

    private func cachedSize(for program: Program) -> Int64 {
        catalogStore.documents(for: program).reduce(Int64(0)) { total, resource in
            guard case .dropbox(let file) = resource.location else { return total }
            return total + (MediaCache.shared.cachedSize(for: file) ?? 0)
        }
    }

    private var totalCachedSize: Int64 {
        MediaCache.shared.totalCacheSize()
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}

#Preview {
    NavigationStack {
        SettingsView(settingsStore: SettingsStore.shared)
            .environmentObject(CatalogStore())
    }
}
