import Foundation

// Used only by the isolated package built by test-spreadsheets.sh. No network or credentials.
enum DropboxConfig {
    static let isConfigured = true
}

@MainActor
enum DropboxService {
    static var files: [DropboxFileMetadata] = []
    static var beforeListing: (() async -> Void)?
    static var listingAttempts = 0

    static func listResourceSpreadsheets() async throws -> [DropboxFileMetadata] {
        listingAttempts += 1
        await beforeListing?()
        return files
    }
}

@MainActor
final class MediaCache {
    static let shared = MediaCache()
    var urls: [String: URL] = [:]
    var downloadFails = false
    var attempts = 0

    func ensureCached(_ file: DropboxFileMetadata) async throws -> URL {
        attempts += 1
        if downloadFails { throw URLError(.notConnectedToInternet) }
        guard let url = urls[file.id] else { throw CocoaError(.fileNoSuchFile) }
        return url
    }

    // Models the real cache's offline fallback, which must not commit a new revision.
    func availableURL(for file: DropboxFileMetadata) async throws -> URL {
        do { return try await ensureCached(file) }
        catch {
            guard let url = urls[file.id] else { throw error }
            return url
        }
    }
}
