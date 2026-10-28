import Foundation

/// A file as returned by Dropbox's list_folder API. Codable (not just
/// Decodable) so it can round-trip through CatalogStore's on-disk snapshot,
/// which is what lets the app show synced content on an offline launch.
struct DropboxFileMetadata: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let pathLower: String
    /// Changes whenever the file's content changes -- used to detect updates.
    let rev: String
    /// Optional so catalogs saved before modification dates were tracked still load.
    var serverModified: String? = nil

    var modifiedDate: Date? {
        guard let serverModified else { return nil }
        return try? Date(serverModified, strategy: .iso8601)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rev
        case pathLower = "path_lower"
        case serverModified = "server_modified"
    }
}

enum DropboxError: LocalizedError {
    case notConfigured
    case authFailed
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return AppLanguage.string("Your training library isn't connected yet. Contact your administrator for help.")
        case .authFailed:
            return AppLanguage.string("The training library connection needs attention. Contact your administrator for help.")
        case .requestFailed(let message):
            return message
        }
    }
}
