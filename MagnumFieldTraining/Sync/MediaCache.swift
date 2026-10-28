import Foundation

/// Thrown when a video needs downloading but Wi-Fi-only downloads are on
/// and the device isn't currently on Wi-Fi.
enum MediaCacheError: LocalizedError {
    case wifiRequired

    var errorDescription: String? {
        "This video isn't downloaded yet, and Wi-Fi-only downloads are turned on. Connect to Wi-Fi, or allow cellular downloads in Settings."
    }
}

/// Downloads and caches Dropbox PDFs and videos on disk so they stay
/// available in the field even without a signal, and avoids re-downloading
/// files that haven't changed since the last sync.
///
/// An `actor` (not a plain class) because `ensureCached`/`clearAll` mutate
/// `manifest`, and this cache is genuinely called from more than one
/// concurrent task in practice -- e.g. CatalogStore's background sync and a
/// WalkthroughDetailView the foreman happens to open at the same time --
/// so unsynchronized mutation of `manifest` was a real data race. The
/// read-only helpers below (`localURL`, `isCached`, `cachedSize`,
/// `totalCacheSize`) never touch `manifest`, so they're marked
/// `nonisolated` and stay callable synchronously from view code, same as
/// before this change.
actor MediaCache {
    static let shared = MediaCache()

    private let cacheDirectory: URL
    private let manifestURL: URL
    private var manifest: [String: String] // file id -> rev at time of download
    /// The in-flight download for each file id, so concurrent callers (a bulk
    /// "Download Now" overlapping with the foreman opening one of those files
    /// directly) join the same download instead of each fetching their own full
    /// copy in parallel -- which was silently doubling data usage on cellular.
    private struct Download {
        let token: UUID
        let revision: String
        let destination: URL
        let allowsCellular: Bool
        let task: Task<Void, Error>
    }
    private var inFlightDownloads: [String: Download] = [:]
    private var generation = 0
    private var isClearing = false
    private var clearingTask: Task<Void, Never>?
    private var pruningIDs: Set<String> = []

    private let isOnWiFi: @Sendable () -> Bool
    private let downloadFile: @Sendable (DropboxFileMetadata, URL, Bool) async throws -> Void

    init(
        cacheDirectory: URL? = nil,
        isOnWiFi: @escaping @Sendable () -> Bool = { NetworkMonitor.shared.isOnWiFi },
        downloadFile: @escaping @Sendable (DropboxFileMetadata, URL, Bool) async throws -> Void = { file, url, allowCellular in
            try await DropboxService.download(file, to: url, allowCellular: allowCellular)
        }
    ) {
        self.downloadFile = downloadFile
        self.isOnWiFi = isOnWiFi
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = cacheDirectory ?? base.appendingPathComponent("DropboxMediaCache", isDirectory: true)
        manifestURL = self.cacheDirectory.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            manifest = decoded
        } else {
            manifest = [:]
        }
        Self.migrateLegacyFiles(in: self.cacheDirectory, manifest: manifest)
    }

    nonisolated func localURL(for file: DropboxFileMetadata) -> URL {
        cacheDirectory.appendingPathComponent(
            Self.cacheFilename(id: file.id, fileExtension: (file.name as NSString).pathExtension)
        )
    }

    /// Dropbox IDs are case-sensitive, while the filesystem may not be.
    /// Hex preserves every byte without relying on filename capitalization.
    nonisolated private static func cacheFilename(id: String, fileExtension: String) -> String {
        let encodedID = id.utf8.map { String(format: "%02x", $0) }.joined()
        let ext = fileExtension.lowercased()
        return ext.isEmpty ? encodedID : "\(encodedID).\(ext)"
    }

    nonisolated private static func migrateLegacyFiles(in directory: URL, manifest: [String: String]) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        let idsByLegacyName = Dictionary(
            manifest.keys.map { ($0.replacingOccurrences(of: ":", with: "_"), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for source in files {
            // Compare the actual directory entry's spelling, not fileExists:
            // a case-insensitive lookup can find another Dropbox file's bytes.
            let legacyName = source.deletingPathExtension().lastPathComponent
            guard let id = idsByLegacyName[legacyName] else { continue }
            let destination = directory.appendingPathComponent(
                cacheFilename(id: id, fileExtension: source.pathExtension)
            )
            guard !manager.fileExists(atPath: destination.path) else { continue }
            try? manager.moveItem(at: source, to: destination)
        }
    }

    nonisolated func isCached(_ file: DropboxFileMetadata) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: file).path)
    }

    private func isUpToDate(_ file: DropboxFileMetadata) -> Bool {
        guard manifest[file.id] == file.rev else { return false }
        return isCached(file)
    }

    /// Whether a file is missing locally, or has changed on Dropbox since it was last
    /// cached -- i.e. whether `ensureCached` would actually need to download it. Used
    /// to tell whether there's anything new to offer in the "New Content Available"
    /// banner, without downloading anything yet.
    func needsDownload(_ file: DropboxFileMetadata) -> Bool {
        !isUpToDate(file)
    }

    /// Returns the local file URL, downloading first if it's missing or has
    /// changed on Dropbox since it was last cached. Videos are skipped (and
    /// `MediaCacheError.wifiRequired` is thrown) when Wi-Fi-only downloads
    /// are on and the device isn't on Wi-Fi, unless `allowCellular` is true.
    @discardableResult
    func ensureCached(_ file: DropboxFileMetadata, allowCellular: Bool = true, requiresWiFi: Bool = false) async throws -> URL {
        try Task.checkCancellation()
        guard !isClearing, !pruningIDs.contains(file.id) else { throw CancellationError() }
        let requestGeneration = generation
        let destination = localURL(for: file)
        if isUpToDate(file) { return destination }
        if (requiresWiFi || (isVideo(file) && !allowCellular)), !isOnWiFi() {
            throw MediaCacheError.wifiRequired
        }
        let permitsCellular = !requiresWiFi && (allowCellular || !isVideo(file))
        if let existing = inFlightDownloads[file.id] {
            do {
                try await existing.task.value
            } catch {
                try Task.checkCancellation()
                guard !(error is CancellationError), generation == requestGeneration, !isClearing,
                      permitsCellular, !existing.allowsCellular else { throw error }
                // A manual request may retry over cellular after the shared Wi-Fi request fails.
                return try await ensureCached(file, allowCellular: allowCellular, requiresWiFi: requiresWiFi)
            }
            try Task.checkCancellation()
            guard generation == requestGeneration, !isClearing else { throw CancellationError() }
            if existing.revision != file.rev || existing.destination != destination {
                return try await ensureCached(file, allowCellular: allowCellular, requiresWiFi: requiresWiFi)
            }
            return destination
        }
        let token = UUID()
        let download = Task {
            // Publish the manifest before any joined caller can start another revision.
            defer {
                if inFlightDownloads[file.id]?.token == token {
                    inFlightDownloads[file.id] = nil
                }
            }
            try await downloadFile(file, destination, permitsCellular)
            try Task.checkCancellation()
            guard generation == requestGeneration, !isClearing else { throw CancellationError() }
            manifest[file.id] = file.rev
            saveManifest()
        }
        inFlightDownloads[file.id] = Download(token: token, revision: file.rev, destination: destination, allowsCellular: permitsCellular, task: download)
        try await download.value
        try Task.checkCancellation()
        guard generation == requestGeneration, !isClearing else { throw CancellationError() }
        return destination
    }

    /// Opening an existing download must still work when its update cannot be fetched.
    /// Bulk downloads use ensureCached so a failed update remains pending.
    func availableURL(for file: DropboxFileMetadata, allowCellular: Bool = true) async throws -> URL {
        let requestGeneration = generation
        do {
            return try await ensureCached(file, allowCellular: allowCellular)
        } catch {
            try Task.checkCancellation()
            guard !(error is CancellationError),
                  generation == requestGeneration,
                  !isClearing,
                  !pruningIDs.contains(file.id),
                  manifest[file.id] != nil,
                  isCached(file) else { throw error }
            return localURL(for: file)
        }
    }

    /// A reader rejected these bytes. Keep the file until an atomic replacement
    /// succeeds, but never treat it as current or use it as an offline fallback.
    func invalidateCachedRevision(for file: DropboxFileMetadata) {
        manifest[file.id] = nil
        saveManifest()
    }

    private func isVideo(_ file: DropboxFileMetadata) -> Bool {
        let ext = (file.name as NSString).pathExtension.lowercased()
        return WalkthroughResource.videoExtensions.contains(ext)
    }

    /// Size on disk of one cached file, or nil if it isn't cached.
    nonisolated func cachedSize(for file: DropboxFileMetadata) -> Int64? {
        let url = localURL(for: file)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.size] as? Int64
    }

    /// Total size on disk of every cached PDF and video, for display in Settings.
    /// Excludes the manifest file itself, which isn't downloaded media -- without this,
    /// the total would never quite reach zero, even right after "Clear Cached Files".
    nonisolated func totalCacheSize() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }
        return contents.reduce(Int64(0)) { total, url in
            guard url != manifestURL else { return total }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    /// Deletes cached files that aren't in the given list -- files removed from
    /// Dropbox since they were cached, or old copies stranded under a different
    /// local filename after a rename. Without this, they'd sit on disk (and count
    /// toward the Settings storage totals) forever, with "Clear Cached Files" as
    /// the only way out. CatalogStore calls this only after a fully-successful
    /// sync, when `files` is known to be the complete current listing.
    func prune(keeping files: [DropboxFileMetadata]) async {
        let keptIDs = Set(files.map(\.id))
        let keptFilenames = Set(files.map { localURL(for: $0).lastPathComponent })
        let obsolete = inFlightDownloads.filter { !keptFilenames.contains($0.value.destination.lastPathComponent) }
        pruningIDs.formUnion(obsolete.keys)
        defer { pruningIDs.subtract(obsolete.keys) }
        for download in obsolete.values { download.task.cancel() }
        for download in obsolete.values { _ = try? await download.task.value }
        if let contents = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for url in contents where url != manifestURL && !keptFilenames.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let removedIDs = manifest.keys.filter { !keptIDs.contains($0) }
        if !removedIDs.isEmpty {
            for id in removedIDs {
                manifest[id] = nil
            }
            saveManifest()
        }
    }

    /// Deletes every cached file and resets the manifest, so everything re-downloads
    /// (respecting Wi-Fi-only rules) the next time it's needed. Used by the "Clear
    /// Cached Files" action in Settings to free up space.
    func clearAll() async {
        if let clearingTask {
            await clearingTask.value
            return
        }
        isClearing = true
        let task = Task { await performClear() }
        clearingTask = task
        await task.value
        clearingTask = nil
    }

    private func performClear() async {
        generation += 1
        let downloads = Array(inFlightDownloads.values)
        for download in downloads { download.task.cancel() }
        // Wait for every writer to stop before deleting anything.
        for download in downloads { _ = try? await download.task.value }
        inFlightDownloads.removeAll()
        defer { isClearing = false }
        if let contents = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for url in contents where url != manifestURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        manifest = [:]
        saveManifest()
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
