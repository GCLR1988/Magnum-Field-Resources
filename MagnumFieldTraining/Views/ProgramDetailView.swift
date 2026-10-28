import SwiftUI

/// Shows one program's walkthroughs -- and, since a program's Dropbox folder can
/// organize files into subfolders (see WalkthroughFolder), any folders nested
/// inside it too. The program's own root is shown by passing only `program`;
/// tapping a subfolder row pushes another ProgramDetailView configured with that
/// `folder`, so the same view recurses to any depth. Pull-to-refresh syncs the
/// whole program from any depth; the other program-level chrome -- download-all,
/// the sync/offline status bar -- only makes sense once, so it's scoped to the
/// root (`folder == nil`) and left off nested subfolder screens.
struct ProgramDetailView: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @EnvironmentObject private var seenStore: SeenStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    let program: Program
    var folder: WalkthroughFolder? = nil
    @State private var isDownloadingAll = false
    @State private var selectedForm: WalkthroughResource?
    @State private var selectedFolderID: String?
    @Environment(\.locale) private var locale

    @State private var selectedMicrosoftApp: MicrosoftTrainingApp?
    @State private var selectedDevice: AppleDevice?

    private var isRoot: Bool { folder == nil }

    private var showsMicrosoftTraining: Bool {
        isRoot && program.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Training Resources") == .orderedSame
    }

    /// The folder tree, re-read fresh from CatalogStore on every render (so
    /// pull-to-refresh and background syncing show up live). A nested subfolder
    /// view re-finds its own folder by id in the current tree. If a sync removed
    /// it, show an empty folder instead of links to files that no longer exist.
    private var currentFolder: WalkthroughFolder {
        guard let folder else { return catalogStore.rootFolder(for: program) }
        return catalogStore.rootFolder(for: program).folder(withID: folder.id)
            ?? WalkthroughFolder(id: folder.id, name: folder.name, resources: [], subfolders: [])
    }

    private var documents: [WalkthroughResource] {
        currentFolder.resources
    }

    private var subfolders: [WalkthroughFolder] {
        currentFolder.subfolders
    }

    private func usesFolderRow(_ folder: WalkthroughFolder) -> Bool {
        program.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Clearstory") == .orderedSame
            && folder.name.localizedStandardContains("video")
    }

    private var tileFolders: [WalkthroughFolder] {
        subfolders.filter { !usesFolderRow($0) }
    }

    private var rowFolders: [WalkthroughFolder] {
        subfolders.filter { usesFolderRow($0) }
    }

    private var isDropboxBacked: Bool {
        if case .dropbox = program.source { return true }
        return false
    }

    var body: some View {
        List {
            Section {
                if !tileFolders.isEmpty || showsMicrosoftTraining {
                    ResourceTileGrid {
                        if showsMicrosoftTraining {
                            ForEach(MicrosoftTrainingApp.allCases) { app in
                                Button {
                                    selectedMicrosoftApp = app
                                } label: {
                                    MicrosoftTrainingTile(app: app)
                                }
                                .buttonStyle(ResourcePressStyle())
                                .bookmarkAction(BookmarkKey.microsoft(app.id))
                            }
                        }
                        ForEach(tileFolders) { child in
                            Button {
                                selectedFolderID = child.id
                            } label: {
                                folderTile(child)
                            }
                            .buttonStyle(ResourcePressStyle())
                            .bookmarkAction(BookmarkKey.folder(child.id))
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 16, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(rowFolders) { child in
                    NavigationLink {
                        ProgramDetailView(program: program, folder: child)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.title2)
                                .foregroundStyle(AppStyle.accent)
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(child.name)
                                    .font(AppStyle.rowTitle)
                                Text(folderCaption(child))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .documentRowStyle()
                    .bookmarkAction(BookmarkKey.folder(child.id))
                }
                ForEach(documents) { resource in
                    if program.isDownloadableForms || program.opensInFormEditor(resource), case .dropbox(let file) = resource.location {
                        DownloadableFormCard(file: file) {
                            selectedForm = resource
                        }
                        .documentRowStyle()
                        .bookmarkAction(resource.persistenceKey)
                    } else {
                        NavigationLink(destination: WalkthroughDetailView(resource: resource)) {
                            WalkthroughRow(resource: resource, logo: catalogStore.logo(for: program), showsTypeLabel: true)
                        }
                        .documentRowStyle()
                    }
                }
            }
            if showsMicrosoftTraining {
                Section {
                    ResourceTileGrid {
                        ForEach(AppleDevice.allCases) { device in
                            Button {
                                selectedDevice = device
                            } label: {
                                DeviceTile(device: device)
                            }
                            .buttonStyle(ResourcePressStyle())
                            .bookmarkAction(BookmarkKey.device(device.id))
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Device Essentials")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color("WarmBackground"))
        .navigationTitle(isRoot ? program.displayName(locale: locale) : currentFolder.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedFolderID) { id in
            if let child = catalogStore.rootFolder(for: program).folder(withID: id) {
                ProgramDetailView(program: program, folder: child)
            } else {
                ContentUnavailableView("Folder unavailable", systemImage: "folder",
                                       description: Text("This folder may have been moved or removed."))
            }
        }
        .navigationDestination(item: $selectedDevice) { device in
            DeviceGettingStartedView(device: device)
        }
        .navigationDestination(item: $selectedMicrosoftApp) { app in
            MicrosoftGettingStartedView(app: app)
        }
        .fullScreenCover(item: $selectedForm) { resource in
            if resource.kind == .pdf {
                FillableFormView(resource: resource)
            } else {
                NavigationStack {
                    WalkthroughDetailView(resource: resource)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") { selectedForm = nil }
                            }
                        }
                }
            }
        }
        .toolbar {
            if isRoot, isDropboxBacked {
                ToolbarItem(placement: .topBarTrailing) {
                    if isDownloadingAll {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task {
                                isDownloadingAll = true
                                await catalogStore.downloadAll(for: program)
                                isDownloadingAll = false
                            }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .disabled(currentFolder.allResources.isEmpty)
                    }
                }
            }
        }
        .refreshable {
            // Syncs at any depth, not just the root -- subfolder contents are
            // looked up live from the freshly-synced tree (see currentFolder),
            // so a pull-to-refresh here actually shows new files.
            await catalogStore.sync(program)
        }
        .task {
            if isRoot, catalogStore.status(for: program) == .idle {
                await catalogStore.sync(program)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isRoot {
                VStack(spacing: 0) {
                    DownloadRecoveryNotice()
                if !networkMonitor.isConnected {
                    StatusNotice(
                        message: Text("You're offline. Downloaded content is available."),
                        systemImage: "wifi.slash"
                    )
                } else if case .failed(let message) = catalogStore.status(for: program) {
                    StatusNotice(
                        message: Text("Couldn't update this program: \(message)"),
                        systemImage: "exclamationmark.circle",
                        isError: true
                    )
                }
            }
            }
        }
        .overlay {
            if documents.isEmpty && subfolders.isEmpty && !showsMicrosoftTraining {
                if isRoot, catalogStore.status(for: program) == .syncing {
                    ResourceLoadingView(title: "Syncing with Dropbox…")
                } else if isRoot {
                    EmptyStateCard {
                        EmptyStateMessage(
                            title: "No walkthroughs yet",
                            systemImage: "doc.text.magnifyingglass",
                            message: Text(emptyStateMessage)
                        )
                    }
                } else {
                    EmptyStateCard {
                        EmptyStateMessage(
                            title: "Empty folder",
                            systemImage: "folder",
                            message: Text("There's nothing in this folder yet.")
                        )
                    }
                }
            }
        }
        .onDisappear {
            // The foreman has now had this list in front of them, so clear
            // any "New" badges for what's currently in it.
            seenStore.markSeen(documents.map(\.persistenceKey))
        }
    }

    /// Each subfolder has its own symbol, with full titles that expand for larger text.
    private func folderTile(_ folder: WalkthroughFolder) -> some View {
        ResourceTile(title: folder.name,
                     subtitle: folderCaption(folder)) {
            FolderArtwork(name: folder.name, logo: folder.logo, isSubfolder: true)
        }
        .accessibilityHint("Opens folder")
    }

    /// e.g. "Folder \u{00B7} 3 items" -- says this is a folder (matching the
    /// "PDF"/"Video" caption walkthrough rows show) while keeping the item count.
    private func folderCaption(_ folder: WalkthroughFolder) -> String {
        let count = folder.allResources.count
        return count == 1
            ? AppLanguage.string("Folder · 1 item", locale: locale)
            : AppLanguage.string("Folder · \(count) items", locale: locale)
    }

    private var emptyStateMessage: String {
        if case .dropbox = program.source, !DropboxConfig.isConfigured {
            return AppLanguage.string("This program isn't connected yet. Contact your administrator for help.", locale: locale)
        }
        return AppLanguage.string("Walkthroughs will appear here when they're added to this program. Pull down to refresh.", locale: locale)
    }
}
