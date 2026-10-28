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
    /// When the most recent fully successful `syncAll()` pass finished --
    /// shown as a single "Last Synced"
    /// line at the bottom of the home screen instead of repeating a per-program
    /// timestamp on every tile.
    @Published private(set) var lastSyncedAt: Date?
    /// This program's whole folder tree (root + nested subfolders), populated by
    /// `sync` for `.dropbox` programs. See `rootFolder(for:)`.
    @Published private(set) var rootFolderByProgram: [String: WalkthroughFolder] = [:]
    /// True when the last sync found files that aren't downloaded yet (syncing
    /// only lists what's in Dropbox; it doesn't fetch the files themselves) --
    /// drives the "New Content Available" banner on the home screen.
    @Published private(set) var hasPendingDownloads: Bool = false
    /// True while `downloadAllPending()` is running, so the banner can show a
    /// downloading state instead of being tappable again mid-download.
    @Published private(set) var isDownloadingPending: Bool = false

    @Published private(set) var failedDownloads: [String: DropboxFileMetadata] = [:]
    @Published private(set) var isClearingCache = false
    private var syncAllTask: Task<Void, Never>?
    private var programSyncTasks: [String: Task<Void, Never>] = [:]
    private var bulkTasks: [UUID: Task<[DropboxFileMetadata], Never>] = [:]
    struct DownloadProgress {
        var completed: Int
        var total: Int
    }
    @Published private(set) var activeDownloads: [UUID: DownloadProgress] = [:]
    var downloadProgress: DownloadProgress {
        DownloadProgress(completed: activeDownloads.values.reduce(0) { $0 + $1.completed },
                         total: activeDownloads.values.reduce(0) { $0 + $1.total })
    }
    private var snapshotWriteTask: Task<Void, Never>?

    init() {
        // Seed with local programs immediately, plus whatever the last successful
        // sync saw in Dropbox (see saveSnapshot) -- so an offline launch still
        // shows every program and walkthrough whose files are cached on disk,
        // instead of "No Programs Yet" until a sync can reach Dropbox again.
        let localPrograms = ProgramData.programs
        if let snapshot = Self.loadSnapshot() {
            programs = snapshot.programs + localPrograms
            rootFolderByProgram = snapshot.rootFolderByProgram
            logoByProgram = snapshot.logoByProgram
            lastSyncedAt = snapshot.lastSyncedAt
            for (programID, folder) in snapshot.rootFolderByProgram {
                documentsByProgram[programID] = folder.allResources
            }
        } else {
            programs = localPrograms
        }
        for program in localPrograms {
            if case .local(let documents) = program.source {
                documentsByProgram[program.id] = documents
                syncStatus[program.id] = .synced(Date())
            }
        }
    }

    #if DEBUG
    /// Isolated sample catalog for visual previews; never reads or writes the live snapshot.
    static func previewCatalog() -> CatalogStore {
        CatalogStore(previewPrograms: [
            Program(name: "Downloadable Forms", source: .dropbox(path: "/Downloadable Forms")),
            Program(name: "Training Resources", source: .dropbox(path: "/Training Resources")),
            Program(name: "Safety", source: .dropbox(path: "/Safety")),
            Program(name: "Procore", source: .dropbox(path: "/Procore"))
        ])
    }

    private init(previewPrograms: [Program]) {
        programs = previewPrograms
        for program in previewPrograms { syncStatus[program.id] = .synced(Date()) }
    }
    #endif

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
        guard !isClearingCache else { return }
        if let task = syncAllTask {
            await task.value
            return
        }
        let task = Task { await performSyncAll() }
        syncAllTask = task
        await task.value
        syncAllTask = nil
    }

    private func performSyncAll() async {
        await refreshPrograms()
        guard !Task.isCancelled, !isClearingCache else { return }
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
                group.addTask { await self.sync(program) }
            }
        }
        guard !Task.isCancelled, !isClearingCache else { return }
        await SpreadsheetStore.shared.sync()
        guard !Task.isCancelled, !isClearingCache else { return }
        let allListingsSucceeded = DropboxConfig.isConfigured
            && SpreadsheetStore.shared.errorMessage == nil
            && discoveryError == nil
            && dropboxPrograms.allSatisfy { program in
                if case .synced = status(for: program) { return true }
                return false
            }
        if allListingsSucceeded {
            lastSyncedAt = Date()
            // Seed the "New" baseline only once every program's listing actually
            // succeeded -- seeding after a partial sync would leave the failed
            // program's pre-existing files out of the baseline, flagging them
            // all "NEW" whenever that program finally syncs.
            // No-op after the very first launch; see SeenStore.seedIfNeeded.
            SeenStore.shared.seedIfNeeded(allDocuments.map { $0.resource.persistenceKey })
            // Safe to evict stale cached files only now: after a partial sync, a
            // failed program's files would look "removed" merely because its
            // listing never arrived.
            await pruneRemovedFiles()
        }
        await saveSnapshot()
        await refreshPendingDownloadsStatus()
        if SettingsStore.shared.autoDownloadOnWiFi {
            Task { await downloadAutomaticallyOnWiFi() }
        }
    }

    /// Re-fetches the file list for one program from Dropbox. Doesn't download the
    /// files themselves -- that's the job of `downloadAll(for:)`/`downloadAllPending()`
    /// (or opening a file directly) -- except the program's logo, which is tiny and
    /// drives the tile icon, so it's always worth fetching: unlike a walkthrough's
    /// PDF or video, a foreman never explicitly asks to download "just the logo".
    func sync(_ program: Program) async {
        guard !isClearingCache, !Task.isCancelled,
              programs.contains(where: { $0.id == program.id }) else { return }
        if let task = programSyncTasks[program.id] {
            await task.value
            return
        }
        let task = Task { await performSync(program) }
        programSyncTasks[program.id] = task
        await task.value
        programSyncTasks[program.id] = nil
    }

    private func performSync(_ program: Program) async {
        guard case .dropbox(let path) = program.source else { return }
        syncStatus[program.id] = .syncing
        do {
            guard DropboxConfig.isConfigured else {
                throw DropboxError.notConfigured
            }
            let contents = try await DropboxService.listFolderContents(path: path, includeAllFiles: program.isDownloadableForms)
            try Task.checkCancellation()
            let rootFolder = WalkthroughFolder.build(
                rootPath: path,
                rootID: program.id,
                rootName: program.name,
                media: contents.media,
                subfolders: contents.subfolders,
                logosByFolder: contents.logosByFolder
            )
            rootFolderByProgram[program.id] = rootFolder
            documentsByProgram[program.id] = rootFolder.allResources
            logoByProgram[program.id] = contents.logo
            syncStatus[program.id] = .synced(Date())
            if syncAllTask == nil { await saveSnapshot() }

            for logo in rootFolder.allLogos {
                try Task.checkCancellation()
                if await MediaCache.shared.needsDownload(logo),
                   let _ = try? await MediaCache.shared.ensureCached(logo, allowCellular: true) {
                    LogoImageCache.shared.invalidate(logo)
                    cacheVersion += 1
                }
            }
        } catch where Task.isCancelled {
            if programs.contains(where: { $0.id == program.id }) {
                syncStatus[program.id] = .idle
            }
        } catch {
            if programs.contains(where: { $0.id == program.id }) {
                syncStatus[program.id] = .failed(error.localizedDescription)
            }
        }
        // A full sync scans once after every folder is ready, rather than rescanning
        // the entire library for each folder while the other listings are still changing.
        if syncAllTask == nil { await refreshPendingDownloadsStatus() }
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
            try Task.checkCancellation()
            programs = discovered + localPrograms
            let currentIDs = Set(programs.map(\.id))
            // A removed program may still have an open detail screen or an in-flight sync.
            for (id, task) in programSyncTasks where !currentIDs.contains(id) {
                task.cancel()
            }
            documentsByProgram = documentsByProgram.filter { currentIDs.contains($0.key) }
            rootFolderByProgram = rootFolderByProgram.filter { currentIDs.contains($0.key) }
            logoByProgram = logoByProgram.filter { currentIDs.contains($0.key) }
            syncStatus = syncStatus.filter { currentIDs.contains($0.key) }
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
        guard !isClearingCache else { return }
        let files = documents(for: program).compactMap { resource -> DropboxFileMetadata? in
            guard case .dropbox(let file) = resource.location else { return nil }
            return file
        }
        await runDownloads(files, allowCellular: true)
        cacheVersion += 1
        await refreshPendingDownloadsStatus()
    }

    /// Automatically caches the current library only when the saved preference
    /// and Wi-Fi connection permit it. Explicit downloads remain independent.
    func downloadAutomaticallyOnWiFi() async {
        guard SettingsStore.shared.autoDownloadOnWiFi, NetworkMonitor.shared.isOnWiFi,
              !isDownloadingPending, !isClearingCache, !Task.isCancelled else { return }
        isDownloadingPending = true
        await runDownloads(downloadableFiles, allowCellular: false, requiresWiFi: true)
        cacheVersion += 1
        isDownloadingPending = false
        await refreshPendingDownloadsStatus()
    }

    func downloadAllPending(allowCellular: Bool = true) async {
        guard !isDownloadingPending, !isClearingCache, !Task.isCancelled else { return }
        isDownloadingPending = true
        await runDownloads(downloadableFiles, allowCellular: allowCellular)
        if !Task.isCancelled, !isClearingCache, !SpreadsheetStore.shared.sourceFiles.isEmpty {
            // Use the tracked sync so clearing the cache can cancel and await this work.
            await syncAll()
        }
        cacheVersion += 1
        isDownloadingPending = false
        await refreshPendingDownloadsStatus()
    }

    /// Checks every currently-known Dropbox file against MediaCache -- without
    /// downloading anything -- to decide whether to show the "New Content
    /// Available" banner. Called after every `syncAll()` and again once
    /// `downloadAllPending()` finishes.
    private var downloadableFiles: [DropboxFileMetadata] {
        let documents = allDocuments.compactMap { item -> DropboxFileMetadata? in
            guard case .dropbox(let file) = item.resource.location else { return nil }
            return file
        }
        return Array(Dictionary((documents + SpreadsheetStore.shared.sourceFiles).map { ($0.id, $0) },
                                uniquingKeysWith: { _, latest in latest }).values)
    }

    private func refreshPendingDownloadsStatus() async {
        let current = downloadableFiles
        let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for id in Array(failedDownloads.keys) {
            guard let file = byID[id] else {
                failedDownloads[id] = nil
                continue
            }
            failedDownloads[id] = await MediaCache.shared.needsDownload(file) ? file : nil
        }
        for file in current {
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
    func noteFileCached() async {
        cacheVersion += 1
        await refreshPendingDownloadsStatus()
    }

    /// Called after Settings clears the media cache, so every row's download-status
    /// icon re-checks MediaCache (everything just became "not downloaded" again)
    /// and the "New Content Available" banner comes back to offer a re-download.
    /// Without this, rows kept their stale "downloaded" icons until the next sync.
    func noteCacheCleared() async {
        cacheVersion += 1
        await refreshPendingDownloadsStatus()
    }

    /// Evicts cached files that no longer correspond to anything in Dropbox --
    /// deleted files, or old copies left under a different local name after a
    /// rename. Only called after a fully-successful `syncAll()`, when the current
    /// program listings are known to be complete. Everything still listed
    /// (including program logos) is kept.
    private func pruneRemovedFiles() async {
        var keep = allDocuments.compactMap { _, resource -> DropboxFileMetadata? in
            guard case .dropbox(let file) = resource.location else { return nil }
            return file
        }
        let programIDs = Set(programs.map(\.id))
        keep += logoByProgram.filter { programIDs.contains($0.key) }.map(\.value)
        keep += rootFolderByProgram.filter { programIDs.contains($0.key) }.values.flatMap(\.allLogos)
        keep += SpreadsheetStore.shared.sourceFiles
        await MediaCache.shared.prune(keeping: keep)
    }

    // MARK: - Offline snapshot

    /// What survives a relaunch: the Dropbox-discovered programs and their folder
    /// trees as of the last successful sync. Written after every successful
    /// program sync and every `syncAll()`; loaded in `init` so an offline launch
    /// still shows everything whose files MediaCache has on disk. `.local`
    /// programs come from ProgramData.swift and aren't persisted.
    private struct CatalogSnapshot: Codable {
        var programs: [Program]
        var rootFolderByProgram: [String: WalkthroughFolder]
        var logoByProgram: [String: DropboxFileMetadata]
        var lastSyncedAt: Date?
    }

    private static var snapshotURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CatalogSnapshot.json")
    }

    private static func loadSnapshot() -> CatalogSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(CatalogSnapshot.self, from: data)
    }

    private func saveSnapshot() async {
        let dropboxPrograms = programs.filter {
            if case .dropbox = $0.source { return true }
            return false
        }
        let programIDs = Set(dropboxPrograms.map(\.id))
        let snapshot = CatalogSnapshot(
            programs: dropboxPrograms,
            rootFolderByProgram: rootFolderByProgram.filter { programIDs.contains($0.key) },
            logoByProgram: logoByProgram.filter { programIDs.contains($0.key) },
            lastSyncedAt: lastSyncedAt
        )
        let url = Self.snapshotURL
        let previous = snapshotWriteTask
        // Serialize writes so an older snapshot can never overwrite a newer one.
        let task = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        snapshotWriteTask = task
        await task.value
    }

    func retryFailedDownloads() async {
        guard !isClearingCache, !isDownloadingPending else { return }
        isDownloadingPending = true
        await refreshPendingDownloadsStatus()
        await runDownloads(Array(failedDownloads.values), allowCellular: true)
        if !Task.isCancelled, !isClearingCache, !SpreadsheetStore.shared.sourceFiles.isEmpty {
            // Use the tracked sync so clearing the cache can cancel and await this work.
            await syncAll()
        }
        isDownloadingPending = false
        cacheVersion += 1
        await refreshPendingDownloadsStatus()
    }

    private func runDownloads(_ files: [DropboxFileMetadata], allowCellular: Bool, requiresWiFi: Bool = false) async {
        guard !isClearingCache, !Task.isCancelled else { return }
        let id = UUID()
        activeDownloads[id] = DownloadProgress(completed: 0, total: files.count)
        let task = Task {
            await Self.downloadConcurrently(files, allowCellular: allowCellular, requiresWiFi: requiresWiFi) { completed, total in
                self.activeDownloads[id] = DownloadProgress(completed: completed, total: total)
            }
        }
        bulkTasks[id] = task
        let failures = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        bulkTasks[id] = nil
        activeDownloads[id] = nil
        guard !isClearingCache, !task.isCancelled else { return }
        for file in files { failedDownloads[file.id] = nil }
        for file in failures { failedDownloads[file.id] = file }
    }

    func clearCachedFiles() async {
        guard !isClearingCache else { return }
        isClearingCache = true
        let sync = syncAllTask
        let programTasks = Array(programSyncTasks.values)
        let downloads = Array(bulkTasks.values)
        sync?.cancel()
        for task in programTasks { task.cancel() }
        for task in downloads { task.cancel() }
        await MediaCache.shared.clearAll()
        await sync?.value
        for task in programTasks { await task.value }
        for task in downloads { _ = await task.value }
        LogoImageCache.shared.clear()
        SpreadsheetStore.shared.clearCache()
        failedDownloads = [:]
        isClearingCache = false
        await noteCacheCleared()
    }

    /// Downloads up to `maxConcurrent` files at once instead of strictly one at a time,
    /// so a program with many walkthroughs doesn't take several times longer to finish
    /// caching than it needs to. Capped (rather than fully unbounded) so a program with
    /// a lot of files doesn't try to open dozens of simultaneous downloads at once and
    /// swamp the connection, or hold that many large videos in flight in memory together.
    private static func downloadConcurrently(
        _ files: [DropboxFileMetadata],
        allowCellular: Bool,
        requiresWiFi: Bool,
        progress: @MainActor (Int, Int) -> Void
    ) async -> [DropboxFileMetadata] {
        var pending: [DropboxFileMetadata] = []
        for file in files {
            guard !Task.isCancelled else { return [] }
            if await MediaCache.shared.needsDownload(file) { pending.append(file) }
        }
        progress(0, pending.count)
        var completed = 0
        var remaining = pending.makeIterator()
        return await withTaskGroup(of: DropboxFileMetadata?.self) { group in
            func enqueue(_ file: DropboxFileMetadata) {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        if requiresWiFi {
                            guard SettingsStore.shared.autoDownloadOnWiFi, NetworkMonitor.shared.isOnWiFi else { return nil }
                        }
                        _ = try await MediaCache.shared.ensureCached(file, allowCellular: allowCellular, requiresWiFi: requiresWiFi)
                        return nil
                    } catch is CancellationError {
                        return nil
                    } catch MediaCacheError.wifiRequired {
                        return nil
                    } catch {
                        return Task.isCancelled ? nil : file
                    }
                }
            }
            for _ in 0..<3 {
                if let file = remaining.next() { enqueue(file) }
            }
            var failures: [DropboxFileMetadata] = []
            while let result = await group.next() {
                completed += 1
                progress(completed, pending.count)
                if let result { failures.append(result) }
                guard !Task.isCancelled else {
                    group.cancelAll()
                    continue
                }
                if requiresWiFi && (!SettingsStore.shared.autoDownloadOnWiFi || !NetworkMonitor.shared.isOnWiFi) {
                    // Drain existing requests without scheduling the rest of the library.
                    continue
                }
                if let file = remaining.next() { enqueue(file) }
            }
            return failures
        }
    }
}
