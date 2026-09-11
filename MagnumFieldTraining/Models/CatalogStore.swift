import Foundation

/// Central, always-current list of programs and their documents.
///
/// Programs come from two places: any `.local` programs hardcoded in
/// ProgramData.swift, plus one Program per top-level folder discovered in
/// this app's dedicated Dropbox folder -- so creating a new Dropbox folder
/// makes a new program appear automatically, no app update needed.
@MainActor
final class CatalogStore: ObservableObject {
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case failed(String)
        case synced(Date)
    }

    @Published private(set) var programs: [Program]
    @Published private(set) var documentsByProgram: [String: [WalkthroughResource]] = [:]
    @Published private(set) var syncStatus: [String: SyncStatus] = [:]
    /// A program's logo file, if one was found in its Dropbox folder (see
    /// DropboxService.FolderContents) -- used as that program's tile icon instead of
    /// the generic folder icon. Keyed by program.id, same as the dictionaries above.
    @Published private(set) var logoByProgram: [String: DropboxFileMetadata] = [:]
    /// Set if the last attempt to discover Dropbox program folders failed. Existing
    /// programs are kept as-is when this happens, rather than being cleared out.
    @Published private(set) var discoveryError: String?
    /// Bumped whenever a background download (in `sync` or `downloadAll`) finishes.
    /// MediaCache itself doesn't publish changes, so views that show cached/download
    /// status (WalkthroughRow's cloud icon, a program's logo tile) read this via
    /// their environment's CatalogStore to know when to re-check MediaCache and
    /// redraw -- otherwise a file that finishes downloading in the background would
    /// keep showing as "not downloaded" until some unrelated state change happened
    /// to force a re-render.
    @Published private(set) var cacheVersion: Int = 0
    /// When the most recent full `syncAll()` pass finished (whether or not every
    /// program's individual sync succeeded) -- shown as a single "Last Synced"
    /// line at the bottom of the home screen instead of repeating a per-program
    /// timestamp on every tile.
    @Published private(set) var lastSyncedAt: Date?
    /// This program's whole folder tree (root + nested subfolders), populated by
    /// `sync` for `.dropbox` programs. See `rootFolder(for:)`.
    @Published private(set) var rootFolderByProgram: [String: WalkthroughFolder] = [:]
    /// True when a returning foreman's last sync found files that weren't eagerly
    /// downloaded (see `sync`'s `eagerlyDownload` parameter) -- drives the "New
    /// Content Available" banner on the home screen.
    @Published private(set) var hasPendingDownloads: Bool = false
    /// True while `downloadAllPending()` is running, so the banner can show a
    /// downloading state instead of being tappable again mid-download.
    @Published private(set) var isDownloadingPending: Bool = false

    init() {
        // Seed with local programs immediately; Dropbox-discovered ones appear after the first sync.
        let localPrograms = ProgramData.programs
        programs = localPrograms
        for program in localPrograms {
            if case .local(let documents) = program.source {
                documentsByProgram[program.id] = documents
                syncStatus[program.id] = .synced(Date())
            }
        }
    }

    func documents(for program: Program) -> [WalkthroughResource] {
        documentsByProgram[program.id] ?? []
    }

    func status(for program: Program) -> SyncStatus {
        syncStatus[program.id] ?? .idle
    }

    func logo(for program: Program) -> DropboxFileMetadata? {
        logoByProgram[program.id]
    }

    /// This program's whole folder tree -- built from Dropbox for `.dropbox`
    /// programs (populated in `sync`), or synthesized as a single subfolder-less
    /// root for `.local` programs -- so views can render either kind the same way.
    func rootFolder(for program: Program) -> WalkthroughFolder {
        rootFolderByProgram[program.id] ?? WalkthroughFolder(
            id: program.id,
            name: program.name,
            resources: documents(for: program),
            subfolders: []
        )
    }

    /// All documents across every program, paired with their program. Used by pinned lookups.
    var allDocuments: [(program: Program, resource: WalkthroughResource)] {
        programs.flatMap { program in
            (documentsByProgram[program.id] ?? []).map { (program, $0) }
        }
    }

    func lookup(persistenceKey: String) -> (program: Program, resource: WalkthroughResource)? {
        allDocuments.first { $0.resource.persistenceKey == persistenceKey }
    }

    /// Discovers program folders in Dropbox, then syncs each one's files. Safe to call
    /// repeatedly (e.g. on launch and pull-to-refresh).
    func syncAll() async {
        // Captured before refreshPrograms/sync run, and before seedIfNeeded below
        // flips it -- true only for the very first sync this app has ever run on
        // this device, which is when everything should download eagerly so the
        // app works fully offline right after install. Every later sync (a later
        // launch, pull-to-refresh) just lists what's there and lets the "New
        // Content Available" banner offer the download instead of blocking
        // launch on it -- that eager download was what made opening slow.
        let isFirstEverSync = !SeenStore.shared.hasSeeded
        await refreshPrograms()
        let dropboxPrograms = programs.filter {
            if case .dropbox = $0.source { return true }
            return false
        }
        // Programs are independent of each other (separate Dropbox folders, separate
        // dictionary keys), so there's no reason to sync them one at a time -- doing
        // so just makes a foreman wait for N sequential round trips on launch and
        // pull-to-refresh instead of letting them overlap.
        await withTaskGroup(of: Void.self) { group in
            for program in dropboxPrograms {
                group.addTask { await self.sync(program, eagerlyDownload: isFirstEverSync) }
            }
        }
        // Only meaningful once Dropbox is actually configured -- otherwise there
        // was nothing to sync, and showing a timestamp would be misleading.
        if DropboxConfig.isConfigured {
            lastSyncedAt = Date()
        }
        // No-op after the very first launch; see SeenStore.seedIfNeeded.
        SeenStore.shared.seedIfNeeded(allDocuments.map { $0.resource.persistenceKey })
        await refreshPendingDownloadsStatus()
    }

    /// Re-fetches the file list for one program from Dropbox and eagerly caches new/changed
    /// files (PDFs and videos alike) so they're available in the field even without a signal.
    func sync(_ program: Program, eagerlyDownload: Bool = true) async {
        guard case .dropbox(let path) = program.source else { return }
        syncStatus[program.id] = .syncing
        do {
            guard DropboxConfig.isConfigured else {
                throw DropboxError.notConfigured
            }
            let contents = try await DropboxService.listFolderContents(path: path)
            let rootFolder = WalkthroughFolder.build(
                rootPath: path,
                rootID: program.id,
                rootName: program.name,
                media: contents.media,
                subfolders: contents.subfolders
            )
            rootFolderByProgram[program.id] = rootFolder
            documentsByProgram[program.id] = rootFolder.allResources
            logoByProgram[program.id] = contents.logo
            syncStatus[program.id] = .synced(Date())

            if eagerlyDownload {
                let allowCellular = !SettingsStore.shared.wifiOnlyForVideos
                await Self.downloadConcurrently(contents.media, allowCellular: allowCellular)
                if let logo = contents.logo {
                    _ = try? await MediaCache.shared.ensureCached(logo, allowCellular: true)
                }
                cacheVersion += 1
            } else if let logo = contents.logo, await MediaCache.shared.needsDownload(logo) {
                // The logo is tiny and drives the program's tile icon, so it's worth
                // fetching even when skipping the rest -- unlike a walkthrough's PDF
                // or video, a foreman never explicitly asks to download "just the logo".
                _ = try? await MediaCache.shared.ensureCached(logo, allowCellular: true)
                cacheVersion += 1
            }
        } catch {
            syncStatus[program.id] = .failed(error.localizedDescription)
        }
    }

    /// Discovers one Program per top-level folder in the Dropbox app folder, and merges
    /// them with any manually defined `.local` programs from ProgramData.swift.
    private func refreshPrograms() async {
        let localPrograms = ProgramData.programs.filter {
            if case .local = $0.source { return true }
            return false
        }

        guard DropboxConfig.isConfigured else {
            discoveryError = nil
            if programs.isEmpty {
                programs = localPrograms
            }
            return
        }

        do {
            let folderNames = try await DropboxService.listFolders(path: "")
            let discovered = folderNames
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { Program(name: $0, source: .dropbox(path: "/\($0)")) }
            programs = discovered + localPrograms
            discoveryError = nil
        } catch {
            discoveryError = error.localizedDescription
            // Keep whatever program list we already had (e.g. from a previous successful
            // discovery) rather than wiping it out on a transient network error.
            if programs.isEmpty {
                programs = localPrograms
            }
        }
    }

    /// Eagerly downloads every file in a program that isn't already cached, so a
    /// foreman can pull a whole program's worth of PDFs and videos to their device
    /// before heading somewhere with no signal. Ignores Wi-Fi-only for videos since
    /// this is an explicit, user-initiated bulk action.
    func downloadAll(for program: Program) async {
        let files = documents(for: program).compactMap { resource -> DropboxFileMetadata? in
            guard case .dropbox(let file) = resource.location else { return nil }
            return file
        }
        await Self.downloadConcurrently(files, allowCellular: true)
        cacheVersion += 1
    }

    /// Downloads every file, across every program, that `syncAll()` listed but
    /// skipped downloading -- triggered by tapping "Download Now" on the New
    /// Content Available banner. An explicit, user-initiated action, so cellular
    /// is allowed the same as `downloadAll(for:)`.
    func downloadAllPending() async {
        guard !isDownloadingPending else { return }
        isDownloadingPending = true
        let files = allDocuments.compactMap { _, resource -> DropboxFileMetadata? in
            guard case .dropbox(let file) = resource.location else { return nil }
            return file
        }
        await Self.downloadConcurrently(files, allowCellular: true)
        cacheVersion += 1
        isDownloadingPending = false
        await refreshPendingDownloadsStatus()
    }

    /// Checks every currently-known Dropbox file against MediaCache -- without
    /// downloading anything -- to decide whether to show the "New Content
    /// Available" banner. Called after every `syncAll()` and again once
    /// `downloadAllPending()` finishes.
    private func refreshPendingDownloadsStatus() async {
        for (_, resource) in allDocuments {
            guard case .dropbox(let file) = resource.location else { continue }
            if await MediaCache.shared.needsDownload(file) {
                hasPendingDownloads = true
                return
            }
        }
        hasPendingDownloads = false
    }

    /// Bumps `cacheVersion` so download-status UI (a walkthrough row's cloud icon,
    /// a program's storage total in Settings) redraws after a file was cached
    /// *outside* of `sync`/`downloadAll` -- specifically, WalkthroughDetailView
    /// downloading a single file on demand when a foreman opens something that
    /// wasn't pre-cached yet. Without this, that row keeps showing its old
    /// "not downloaded" cloud icon after going back, since nothing on CatalogStore
    /// changed to tell SwiftUI to re-check MediaCache for it.
    func noteFileCached() {
        cacheVersion += 1
    }

    /// Downloads up to `maxConcurrent` files at once instead of strictly one at a time,
    /// so a program with many walkthroughs doesn't take several times longer to finish
    /// caching than it needs to. Capped (rather than fully unbounded) so a program with
    /// a lot of files doesn't try to open dozens of simultaneous downloads at once and
    /// swamp the connection, or hold that many large videos in flight in memory together.
    private static func downloadConcurrently(_ files: [DropboxFileMetadata], allowCellular: Bool) async {
        guard !files.isEmpty else { return }
        let maxConcurrent = 3
        var remaining = files
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(maxConcurrent, remaining.count) {
                let file = remaining.removeFirst()
                group.addTask { _ = try? await MediaCache.shared.ensureCached(file, allowCellular: allowCellular) }
            }
            while await group.next() != nil {
                guard !remaining.isEmpty else { continue }
                let file = remaining.removeFirst()
                group.addTask { _ = try? await MediaCache.shared.ensureCached(file, allowCellular: allowCellular) }
            }
        }
    }
}
