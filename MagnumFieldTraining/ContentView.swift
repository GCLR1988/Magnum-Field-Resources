import SwiftUI
import UIKit
import Foundation

struct ContentView: View {
    @EnvironmentObject private var pinnedStore: PinnedStore
    @EnvironmentObject private var catalogStore: CatalogStore
    @EnvironmentObject private var seenStore: SeenStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @State private var showSettings = false
    @State private var selectedProgram: Program?
    /// True until the very first sync (see the `.task` below) finishes, so the
    /// Magnum logo covers the moment before programs have loaded instead of a
    /// flash of the "No Programs Yet" empty state.
    @State private var showSplash = true

    private let programGridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var pinnedDocuments: [(program: Program, resource: WalkthroughResource)] {
        catalogStore.allDocuments.filter { pinnedStore.isPinned($0.resource.persistenceKey) }
    }

    var body: some View {
        ZStack {
            NavigationStack {
                List {
                    if !pinnedDocuments.isEmpty {
                        Section {
                            ForEach(pinnedDocuments, id: \.resource.id) { item in
                                NavigationLink(destination: WalkthroughDetailView(resource: item.resource)) {
                                    WalkthroughRow(resource: item.resource, subtitle: item.program.name)
                                }
                                .cardRowStyle()
                            }
                        } header: {
                            sectionHeader("Pinned")
                        }
                    }
                    if !catalogStore.programs.isEmpty {
                        Section {
                            LazyVGrid(columns: programGridColumns, spacing: 12) {
                                ForEach(catalogStore.programs) { program in
                                    Button {
                                        selectedProgram = program
                                    } label: {
                                        programTile(program)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        } header: {
                            sectionHeader("Programs")
                        }
                    }
                }
                .listSectionSpacing(.custom(24))
                .scrollContentBackground(.hidden)
                .background(Color("WarmBackground"))
                .overlay {
                    if pinnedDocuments.isEmpty && catalogStore.programs.isEmpty {
                        EmptyStateCard {
                            ContentUnavailableView(
                                "No Programs Yet",
                                systemImage: "folder.badge.questionmark",
                                description: Text(DropboxConfig.isConfigured
                                    ? "Create a folder in your Dropbox app folder and pull to refresh."
                                    : "Add your Dropbox app details in DropboxConfig.swift, or define a program in ProgramData.swift.")
                            )
                        }
                    }
                }
                .navigationTitle("Training Depot")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 6) {
                            Image("LogoMark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                            Text("Training Depot")
                                .font(.headline)
                                .foregroundStyle(Color("AccentColor"))
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView(settingsStore: SettingsStore.shared)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { showSettings = false }
                                }
                            }
                    }
                }
                .navigationDestination(item: $selectedProgram) { program in
                    ProgramDetailView(program: program)
                }
                .safeAreaInset(edge: .bottom) {
                    if !networkMonitor.isConnected {
                        Text("You're offline \u{2014} showing downloaded content")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(.secondary)
                    } else if let discoveryError = catalogStore.discoveryError {
                        Text("Couldn't check Dropbox for programs: \(discoveryError)")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(.red)
                    } else if let lastSyncedText {
                        Text(lastSyncedText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(.thinMaterial)
                    }
                }
                .refreshable {
                    await catalogStore.syncAll()
                }
                .task {
                    await catalogStore.syncAll()
                    withAnimation(.easeOut(duration: 0.4)) {
                        showSplash = false
                    }
                }
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
            }

            if !showSplash {
                newContentBanner
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: catalogStore.hasPendingDownloads)
    }

    /// Floating pill in the bottom-right corner offering to download whatever a
    /// non-eager sync (see CatalogStore.sync's `eagerlyDownload` parameter) found
    /// but skipped, so opening the app doesn't have to wait on it. Only appears
    /// once there's actually something pending, and hides itself again once
    /// `downloadAllPending()` finishes.
    @ViewBuilder
    private var newContentBanner: some View {
        if catalogStore.hasPendingDownloads {
            Button {
                Task { await catalogStore.downloadAllPending() }
            } label: {
                HStack(spacing: 8) {
                    if catalogStore.isDownloadingPending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(catalogStore.isDownloadingPending ? "Downloading\u{2026}" : "New Content Available!")
                            .font(.caption.weight(.semibold))
                        if !catalogStore.isDownloadingPending {
                            Text("Download Now")
                                .font(.caption2)
                                .opacity(0.85)
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color("AccentColor"), in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(catalogStore.isDownloadingPending)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("AccentColor"))
            Rectangle()
                .fill(Color("AccentColor").opacity(0.4))
                .frame(width: 36, height: 2)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }

    private func programTile(_ program: Program) -> some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                programIcon(program)

                if catalogStore.status(for: program) == .syncing {
                    ProgressView()
                        .controlSize(.mini)
                        .offset(x: 4, y: -4)
                } else if hasNewDocuments(program) {
                    Circle()
                        .fill(Color("AccentColor"))
                        .frame(width: 10, height: 10)
                        .offset(x: 2, y: -2)
                }
            }

            VStack(spacing: 2) {
                Text(program.name)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let subtitle = subtitle(for: program) {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color("WarmCard"))
        )
    }

    /// The program's own logo when its Dropbox folder has one (see
    /// DropboxService.FolderContents), shown at its natural colors on a plain card
    /// so branded logos don't get tinted by the app's accent color. Falls back to
    /// the generic folder icon otherwise -- e.g. before the first sync finishes, or
    /// for a `.local` program that doesn't have a Dropbox folder to put a logo in.
    @ViewBuilder
    private func programIcon(_ program: Program) -> some View {
        if let logo = catalogStore.logo(for: program), let image = cachedLogoImage(logo) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .frame(width: 56, height: 56)
                .background(Color("WarmBackground"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Image(systemName: "folder.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color("AccentColor"))
                .frame(width: 56, height: 56)
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

    private func hasNewDocuments(_ program: Program) -> Bool {
        catalogStore.documents(for: program).contains { seenStore.isNew($0.persistenceKey) }
    }

    /// Shown under a program's tile name only when there's something worth calling
    /// out -- a sync in progress, or a failed one -- not the plain walkthrough count,
    /// which used to always show here and was removed per user request to keep each
    /// tile down to just its name (and icon/logo) in the normal, synced case.
    private func subtitle(for program: Program) -> String? {
        let count = catalogStore.documents(for: program).count
        switch catalogStore.status(for: program) {
        case .failed:
            return "Sync failed \u{2014} showing \(count) downloaded"
        case .syncing where count == 0:
            return "Syncing\u{2026}"
        default:
            return nil
        }
    }

    /// One "Last Synced" line for the whole screen (see the bottom safeAreaInset)
    /// instead of repeating a per-program timestamp on every tile.
    private var lastSyncedText: String? {
        guard let lastSyncedAt = catalogStore.lastSyncedAt else { return nil }
        return "Last synced \(Self.relativeDateFormatter.localizedString(for: lastSyncedAt, relativeTo: Date()))"
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

#Preview {
    ContentView()
        .environmentObject(PinnedStore())
        .environmentObject(CatalogStore())
        .environmentObject(SeenStore())
        .environmentObject(NetworkMonitor.shared)
}
