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

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheDirectory = base.appendingPathComponent("DropboxMediaCache", isDirectory: true)
        manifestURL = cacheDirectory.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            manifest = decoded
        } else {
            manifest = [:]
        }
    }

    nonisolated func localURL(for file: DropboxFileMetadata) -> URL {
        let safeID = file.id.replacingOccurrences(of: ":", with: "_")
        let ext = (file.name as NSString).pathExtension
        return cacheDirectory.appendingPathComponent(ext.isEmpty ? safeID : "\(safeID).\(ext)")
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
    func ensureCached(_ file: DropboxFileMetadata, allowCellular: Bool = true) async throws -> URL {
        let destination = localURL(for: file)
        if isUpToDate(file) {
            return destination
        }
        if isVideo(file), !allowCellular, !NetworkMonitor.shared.isOnWiFi {
            throw MediaCacheError.wifiRequired
        }
        try await DropboxService.download(file, to: destination)
        manifest[file.id] = file.rev
        saveManifest()
        return destination
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

    /// Deletes every cached file and resets the manifest, so everything re-downloads
    /// (respecting Wi-Fi-only rules) the next time it's needed. Used by the "Clear
    /// Cached Files" action in Settings to free up space.
    func clearAll() {
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
