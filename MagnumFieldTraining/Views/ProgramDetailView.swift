import SwiftUI
import UIKit

/// Shows one program's walkthroughs -- and, since a program's Dropbox folder can
/// organize files into subfolders (see WalkthroughFolder), any folders nested
/// inside it too. The program's own root is shown by passing only `program`;
/// tapping a subfolder row pushes another ProgramDetailView configured with that
/// `folder`, so the same view recurses to any depth. Program-level actions --
/// download-all, pull-to-refresh, the sync/offline status bar -- only make sense
/// once, so they're scoped to the root (`folder == nil`) and left off nested
/// subfolder screens.
struct ProgramDetailView: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @EnvironmentObject private var seenStore: SeenStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    let program: Program
    var folder: WalkthroughFolder? = nil
    @State private var isDownloadingAll = false

    private var isRoot: Bool { folder == nil }

    /// The folder tree, re-read fresh from CatalogStore on every render at the
    /// root (so pull-to-refresh and background syncing show up live); a nested
    /// subfolder view instead renders the snapshot it was pushed with.
    private var currentFolder: WalkthroughFolder {
        folder ?? catalogStore.rootFolder(for: program)
    }

    private var documents: [WalkthroughResource] {
        currentFolder.resources
    }

    private var subfolders: [WalkthroughFolder] {
        currentFolder.subfolders
    }

    private var isDropboxBacked: Bool {
        if case .dropbox = program.source { return true }
        return false
    }

    var body: some View {
        List {
            ForEach(subfolders) { child in
                NavigationLink(destination: ProgramDetailView(program: program, folder: child)) {
                    folderRow(child)
                }
                .cardRowStyle()
            }
            ForEach(documents) { resource in
                NavigationLink(destination: WalkthroughDetailView(resource: resource)) {
                    WalkthroughRow(resource: resource, logo: catalogStore.logo(for: program), showsTypeLabel: true)
                }
                .cardRowStyle()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("WarmBackground"))
        .navigationTitle(isRoot ? program.name : currentFolder.name)
        .navigationBarTitleDisplayMode(.inline)
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
            if isRoot {
                await catalogStore.sync(program, eagerlyDownload: false)
            }
        }
        .task {
            if isRoot, catalogStore.status(for: program) == .idle {
                await catalogStore.sync(program, eagerlyDownload: false)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isRoot {
                if !networkMonitor.isConnected {
                    Text("You're offline \u{2014} showing downloaded content")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.secondary)
                } else if case .failed(let message) = catalogStore.status(for: program) {
                    Text("Couldn't sync: \(message)")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.red)
                }
            }
        }
        .overlay {
            if documents.isEmpty && subfolders.isEmpty {
                if isRoot, catalogStore.status(for: program) == .syncing {
                    ProgressView("Syncing with Dropbox\u{2026}")
                } else if isRoot {
                    EmptyStateCard {
                        ContentUnavailableView(
                            "No Walkthroughs Yet",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(emptyStateMessage)
                        )
                    }
                } else {
                    EmptyStateCard {
                        ContentUnavailableView(
                            "Empty Folder",
                            systemImage: "folder",
                            description: Text("There's nothing in this folder yet.")
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

    /// A tappable row for a subfolder, styled like a walkthrough row so the two
    /// read as one consistent list. Shows a small accent dot -- the same "new"
    /// indicator used on individual walkthroughs -- when anything anywhere
    /// inside this folder hasn't been seen yet, so a foreman knows where to look.
    private func folderRow(_ folder: WalkthroughFolder) -> some View {
        HStack(spacing: 12) {
            folderIcon

            VStack(alignment: .center, spacing: 2) {
                HStack(spacing: 6) {
                    Text(folder.name)
                        .multilineTextAlignment(.center)
                    if hasNewDocuments(folder) {
                        Circle()
                            .fill(Color("AccentColor"))
                            .frame(width: 8, height: 8)
                    }
                }
                Text(folderCaption(folder))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
    }

    /// Shows the program's logo, same as its home-screen tile and its
    /// walkthrough rows, so a folder reads as belonging to the same program
    /// instead of a generic filesystem icon. Falls back to a plain folder icon
    /// when the program has no logo (or it hasn't downloaded yet).
    @ViewBuilder
    private var folderIcon: some View {
        if let logo = catalogStore.logo(for: program), let image = cachedLogoImage(logo) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .frame(width: 32, height: 32)
                .background(Color("WarmBackground"), in: Circle())
        } else {
            Image(systemName: "folder.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("AccentColor"))
                .frame(width: 32, height: 32)
                .background(Color("AccentColor").opacity(0.15), in: Circle())
        }
    }

    private func cachedLogoImage(_ file: DropboxFileMetadata) -> Image? {
        guard MediaCache.shared.isCached(file),
              let uiImage = UIImage(contentsOfFile: MediaCache.shared.localURL(for: file).path) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }

    private func hasNewDocuments(_ folder: WalkthroughFolder) -> Bool {
        folder.allResources.contains { seenStore.isNew($0.persistenceKey) }
    }

    /// e.g. "Folder \u{00B7} 3 items" -- says this is a folder (matching the
    /// "PDF"/"Video" caption walkthrough rows show) while keeping the item count.
    private func folderCaption(_ folder: WalkthroughFolder) -> String {
        let count = folder.allResources.count
        let itemsText = count == 1 ? "1 item" : "\(count) items"
        return "Folder \u{00B7} \(itemsText)"
    }

    private var emptyStateMessage: String {
        if case .dropbox = program.source, !DropboxConfig.isConfigured {
            return "Add your Dropbox app details in DropboxConfig.swift to sync this program's files (see DROPBOX_SETUP.md)."
        }
        return "Add PDFs or videos to this program's Dropbox folder, or edit ProgramData.swift."
    }
}
