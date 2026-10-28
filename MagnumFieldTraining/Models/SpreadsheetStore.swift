import Foundation
import Observation

@MainActor
@Observable
final class SpreadsheetStore {
    static let shared = SpreadsheetStore()

    private(set) var contacts: [EmployeeContact] = []
    private(set) var links: [UsefulLink] = []
    private(set) var hasDirectory = false
    private(set) var hasLinks = false
    private(set) var isSyncing = false
    private(set) var errorMessage: String?
    private(set) var sourceFiles: [DropboxFileMetadata] = []
    private(set) var isLocalPreview = false
    private var directoryRevision: String?
    private var linksRevision: String?
    private var syncTask: Task<Void, Never>?

    private struct Snapshot: Codable {
        let contacts: [EmployeeContact]
        let links: [UsefulLink]
        let hasDirectory: Bool
        let hasLinks: Bool
        let directoryRevision: String?
        let linksRevision: String?
        let sourceFiles: [DropboxFileMetadata]
    }

    private let snapshotURL: URL

    private static var defaultSnapshotURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpreadsheetResources.json")
    }

    init(snapshotURL: URL? = nil) {
        self.snapshotURL = snapshotURL ?? Self.defaultSnapshotURL
        if let data = try? Data(contentsOf: self.snapshotURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            contacts = snapshot.contacts
            links = snapshot.links
            hasDirectory = snapshot.hasDirectory
            hasLinks = snapshot.hasLinks
            directoryRevision = snapshot.directoryRevision
            linksRevision = snapshot.linksRevision
            sourceFiles = snapshot.sourceFiles
        }
    }

    func sync() async {
        guard !isLocalPreview, DropboxConfig.isConfigured else { return }
        // All callers must wait for the same refresh before trusting its listing or error state.
        if let syncTask {
            await syncTask.value
            return
        }
        guard !isSyncing else { return }
        let task = Task { await performSync() }
        syncTask = task
        await task.value
        syncTask = nil
    }

    private func performSync() async {
        guard !Task.isCancelled else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let files = try await DropboxService.listResourceSpreadsheets()
            try Task.checkCancellation()
            let directories = files.filter { $0.name.lowercased() != "useful links.xlsx" }
            let linkFiles = files.filter { $0.name.lowercased() == "useful links.xlsx" }
            guard directories.count <= 1, linkFiles.count <= 1 else {
                throw SpreadsheetError.invalid(AppLanguage.string("More than one directory or Useful Links workbook was found. Keep one copy of each in the connected Dropbox folder."))
            }
            sourceFiles = files
            var errors: [String] = []
            if let file = directories.first {
                hasDirectory = true
                do {
                    let revision = file.id + ":" + file.rev
                    if directoryRevision != revision {
                        // Only label parsed data with this revision after its download succeeds.
                        let url = try await MediaCache.shared.ensureCached(file)
                        let parsed = try await Task.detached(priority: .userInitiated) {
                            try SpreadsheetResources.contacts(from: url)
                        }.value
                        try Task.checkCancellation()
                        contacts = parsed
                        directoryRevision = revision
                    }
                } catch {
                    if Task.isCancelled { return }
                    errors.append(AppLanguage.string("Company Directory: \(error.localizedDescription)"))
                }
            } else {
                contacts = []
                hasDirectory = false
                directoryRevision = nil
            }
            if let file = linkFiles.first {
                hasLinks = true
                do {
                    let revision = file.id + ":" + file.rev
                    if linksRevision != revision {
                        // Only label parsed data with this revision after its download succeeds.
                        let url = try await MediaCache.shared.ensureCached(file)
                        let parsed = try await Task.detached(priority: .userInitiated) {
                            try SpreadsheetResources.links(from: url)
                        }.value
                        try Task.checkCancellation()
                        links = parsed
                        linksRevision = revision
                    }
                } catch {
                    if Task.isCancelled { return }
                    errors.append(AppLanguage.string("Useful Links: \(error.localizedDescription)"))
                }
            } else {
                links = []
                hasLinks = false
                linksRevision = nil
            }
            try Task.checkCancellation()
            errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
            try save()
        } catch {
            if !Task.isCancelled {
                errorMessage = AppLanguage.string("Couldn't update company resources. \(error.localizedDescription)")
            }
        }
    }

    private func save() throws {
        let snapshot = Snapshot(contacts: contacts, links: links,
                                hasDirectory: hasDirectory, hasLinks: hasLinks,
                                directoryRevision: directoryRevision, linksRevision: linksRevision,
                                sourceFiles: sourceFiles)
        let url = snapshotURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
    }

    func clearCache() {
        // Prevent a suspended refresh from restoring the snapshot after it is cleared.
        syncTask?.cancel()
        contacts = []
        links = []
        directoryRevision = nil
        linksRevision = nil
        errorMessage = nil
        try? FileManager.default.removeItem(at: snapshotURL)
    }

    #if DEBUG
    private var previewSnapshot: Snapshot?

    /// Local previews are in-memory only and never replace the Dropbox connection.
    func preview(url: URL, directory: Bool) async throws {
        guard !isSyncing else {
            throw SpreadsheetError.invalid(AppLanguage.string("Wait for syncing to finish, then try again."))
        }
        isSyncing = true
        defer { isSyncing = false }
        let original = Snapshot(contacts: contacts, links: links,
                                hasDirectory: hasDirectory, hasLinks: hasLinks,
                                directoryRevision: directoryRevision, linksRevision: linksRevision,
                                sourceFiles: sourceFiles)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if directory {
            contacts = try await Task.detached { try SpreadsheetResources.contacts(from: url) }.value
            hasDirectory = true
        } else {
            links = try await Task.detached { try SpreadsheetResources.links(from: url) }.value
            hasLinks = true
        }
        if !isLocalPreview { previewSnapshot = original }
        isLocalPreview = true
        errorMessage = nil
    }

    func endPreview() async {
        isLocalPreview = false
        if let snapshot = previewSnapshot {
            contacts = snapshot.contacts
            links = snapshot.links
            hasDirectory = snapshot.hasDirectory
            hasLinks = snapshot.hasLinks
            directoryRevision = snapshot.directoryRevision
            linksRevision = snapshot.linksRevision
            sourceFiles = snapshot.sourceFiles
        }
        previewSnapshot = nil
        await sync()
    }
    #endif
}
