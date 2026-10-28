import SwiftUI

/// Settings screen: the Wi-Fi-only-for-videos toggle, plus a Storage section
/// for seeing how much space downloaded PDFs and videos are using and
/// clearing them if a foreman's device is running low.
struct SettingsView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var settingsStore: SettingsStore
    @EnvironmentObject private var catalogStore: CatalogStore
    @State private var showClearCacheConfirm = false
    @State private var cachedSizes: [String: Int64] = [:]
    @State private var totalCachedSize: Int64 = 0

    private struct StorageRequest: Equatable {
        let cacheVersion: Int
        let files: [String: [DropboxFileMetadata]]
    }

    private var storageRequest: StorageRequest {
        StorageRequest(cacheVersion: catalogStore.cacheVersion, files: Dictionary(
            uniqueKeysWithValues: dropboxPrograms.map { program in
                (program.id, catalogStore.documents(for: program).compactMap { resource in
                    if case .dropbox(let file) = resource.location { return file }
                    return nil
                })
            }
        ))
    }

    var body: some View {
        Form {
            Section("Help") {
                NavigationLink {
                    AppGuideView()
                } label: {
                    Label("How to Use This App", systemImage: "questionmark.circle")
                }
            }

            Section {
                Toggle("Auto-Download All on Wi-Fi", isOn: $settingsStore.autoDownloadOnWiFi)
            } header: {
                Text("Automatic Downloads")
            } footer: {
                Text("Automatically download new and updated files while the app is active on Wi-Fi. Downloads resume when you reopen the app or reconnect to Wi-Fi.")
            }

            Section {
                Toggle("Wi-Fi Only for Videos", isOn: $settingsStore.wifiOnlyForVideos)
            } header: {
                Text("Data Usage")
            } footer: {
                Text("Use Wi-Fi for videos to save cellular data. You can still choose \"Download Anyway\" or download all files. PDFs can download over cellular.")
            }

            Section {
                ForEach(dropboxPrograms) { program in
                    HStack {
                        Text(program.displayName(locale: locale))
                        Spacer()
                        Text(Self.byteFormatter.string(fromByteCount: cachedSizes[program.id, default: 0]))
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
                .disabled(totalCachedSize == 0 || catalogStore.isClearingCache)
            } header: {
                Text("Storage")
            } footer: {
                Text("Downloaded files are available offline. Clearing them frees up space; you'll need a connection to open them again.")
            }

            Section {
                NavigationLink {
                    HardHatGameView()
                } label: {
                    Label("Do Not Press This Button", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppStyle.accent)
                        .frame(minHeight: 44)
                }
            }
        }
        .task(id: storageRequest) {
            let request = storageRequest
            // File attributes and directory enumeration must not block scrolling.
            let snapshot = await Task.detached(priority: .utility) {
                let sizes = request.files.mapValues { files in
                    files.reduce(Int64(0)) { $0 + (MediaCache.shared.cachedSize(for: $1) ?? 0) }
                }
                return (sizes, MediaCache.shared.totalCacheSize())
            }.value
            guard !Task.isCancelled else { return }
            cachedSizes = snapshot.0
            totalCachedSize = snapshot.1
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
                    await catalogStore.clearCachedFiles()
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
