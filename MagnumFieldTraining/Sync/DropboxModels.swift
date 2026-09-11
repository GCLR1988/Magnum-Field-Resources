import Foundation

/// A file as returned by Dropbox's list_folder API.
struct DropboxFileMetadata: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let pathLower: String
    /// Changes whenever the file's content changes -- used to detect updates.
    let rev: String

    private enum CodingKeys: String, CodingKey {
        case id, name, rev
        case pathLower = "path_lower"
    }
}

enum DropboxError: LocalizedError {
    case notConfigured
    case authFailed
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Dropbox sync isn't set up yet. Fill in DropboxConfig.swift (see DROPBOX_SETUP.md)."
        case .authFailed:
            return "Couldn't authenticate with Dropbox. Double-check the app key/secret/refresh token in DropboxConfig.swift."
        case .requestFailed(let message):
            return message
        }
    }
}
