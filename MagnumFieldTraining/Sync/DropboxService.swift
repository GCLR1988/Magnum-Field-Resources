import Foundation

/// Talks to the Dropbox API to list and download PDFs and videos from a
/// folder inside this app's dedicated "App folder".
enum DropboxService {
    private static let supportedExtensions: Set<String> = ["pdf", "mp4", "mov", "m4v"]
    private static let logoExtensions: Set<String> = ["png", "jpg", "jpeg"]

    /// A program folder's walkthrough files (from anywhere in its folder tree, so
    /// programs can organize files into subfolders), its optional logo, and the
    /// subfolders themselves -- all from one recursive pass over that folder's
    /// contents (see `listFolderContents`).
    struct FolderContents {
        let media: [DropboxFileMetadata]
        let logo: DropboxFileMetadata?
        let subfolders: [Subfolder]

        /// A subfolder found anywhere under a program's Dropbox folder, at any depth.
        struct Subfolder {
            let path: String   // lowercase Dropbox path, e.g. "/procore/estimating"
            let name: String
        }
    }

    private struct ListFolderRequest: Encodable {
        let path: String
        let recursive: Bool
    }

    private struct ListFolderResponse: Decodable {
        let entries: [Entry]
        let cursor: String
        let has_more: Bool
    }

    private struct Entry: Decodable {
        let tag: String
        let id: String?
        let name: String?
        let path_lower: String?
        let rev: String?

        private enum CodingKeys: String, CodingKey {
            case tag = ".tag"
            case id, name, path_lower, rev
        }
    }

    /// Lists everything under a program folder -- its own PDFs/videos, any nested
    /// inside subfolders (so a program can organize its walkthroughs into folders
    /// like "Estimating" or "Scheduling"), those subfolders themselves, and the
    /// program's logo if one is present directly in its root -- a file named
    /// "logo.png"/"logo.jpg"/"logo.jpeg" (case-insensitive), used as that program's
    /// tile icon instead of the generic folder icon. `path` is relative to the app's
    /// dedicated Dropbox folder, e.g. "/Procore".
    static func listFolderContents(path: String) async throws -> FolderContents {
        let allEntries = try await listAllEntries(path: path, recursive: true)
        let files = allEntries.compactMap { entry -> DropboxFileMetadata? in
            guard entry.tag == "file",
                  let id = entry.id, let name = entry.name,
                  let pathLower = entry.path_lower, let rev = entry.rev else { return nil }
            return DropboxFileMetadata(id: id, name: name, pathLower: pathLower, rev: rev)
        }
        let media = files.filter { isSupportedMediaFile($0.name) }

        // Only a logo dropped directly in the program's own root counts -- one dropped
        // inside a subfolder is just treated as a regular (oddly-named) walkthrough file.
        let rootLower = path.lowercased()
        let logo = files.first { file in
            isLogoFile(file.name) && (file.pathLower as NSString).deletingLastPathComponent == rootLower
        }

        let subfolders = allEntries.compactMap { entry -> FolderContents.Subfolder? in
            guard entry.tag == "folder", let name = entry.name, let pathLower = entry.path_lower else { return nil }
            return FolderContents.Subfolder(path: pathLower, name: name)
        }

        return FolderContents(media: media, logo: logo, subfolders: subfolders)
    }

    /// Lists the names of subfolders directly inside the given folder path (relative to the
    /// app's dedicated Dropbox folder). Used to auto-discover one Program per folder.
    static func listFolders(path: String) async throws -> [String] {
        let allEntries = try await listAllEntries(path: path)
        return allEntries.compactMap { entry in
            guard entry.tag == "folder", let name = entry.name else { return nil }
            return name
        }
    }

    private static func listAllEntries(path: String, recursive: Bool = false) async throws -> [Entry] {
        var response = try await listFolder(path: path, recursive: recursive)
        var allEntries = response.entries
        while response.has_more {
            response = try await listFolderContinue(cursor: response.cursor)
            allEntries.append(contentsOf: response.entries)
        }
        return allEntries
    }

    private static func isSupportedMediaFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    /// A program's logo is just a file named "logo" (any case) with an image extension,
    /// dropped in that program's own Dropbox folder alongside its PDFs/videos.
    private static func isLogoFile(_ name: String) -> Bool {
        let base = (name as NSString).deletingPathExtension.lowercased()
        let ext = (name as NSString).pathExtension.lowercased()
        return base == "logo" && logoExtensions.contains(ext)
    }

    private static func listFolder(path: String, recursive: Bool) async throws -> ListFolderResponse {
        let token = try await DropboxAuthService.shared.accessToken()
        guard let url = URL(string: "https://api.dropboxapi.com/2/files/list_folder") else {
            throw DropboxError.requestFailed("Invalid Dropbox request URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ListFolderRequest(path: path, recursive: recursive))

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        try checkOK(urlResponse, data: data, context: "listing folder \"\(path)\"")
        return try JSONDecoder().decode(ListFolderResponse.self, from: data)
    }

    private static func listFolderContinue(cursor: String) async throws -> ListFolderResponse {
        let token = try await DropboxAuthService.shared.accessToken()
        guard let url = URL(string: "https://api.dropboxapi.com/2/files/list_folder/continue") else {
            throw DropboxError.requestFailed("Invalid Dropbox request URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["cursor": cursor])

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        try checkOK(urlResponse, data: data, context: "continuing folder listing")
        return try JSONDecoder().decode(ListFolderResponse.self, from: data)
    }

    /// Downloads a file's content to a local destination URL.
    static func download(_ file: DropboxFileMetadata, to destination: URL) async throws {
        let token = try await DropboxAuthService.shared.accessToken()
        guard let url = URL(string: "https://content.dropboxapi.com/2/files/download") else {
            throw DropboxError.requestFailed("Invalid Dropbox request URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let argJSON = try JSONEncoder().encode(["path": file.pathLower])
        request.setValue(String(data: argJSON, encoding: .utf8), forHTTPHeaderField: "Dropbox-API-Arg")

        let (tempURL, urlResponse) = try await URLSession.shared.download(for: request)
        guard let http = urlResponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw DropboxError.requestFailed("Couldn't download \(file.name).")
        }
        try FileManager.default.moveOrReplaceItem(at: tempURL, to: destination)
    }

    private static func checkOK(_ response: URLResponse, data: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DropboxError.requestFailed("No response from Dropbox while \(context).")
        }
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "status \(http.statusCode)"
            throw DropboxError.requestFailed("Dropbox returned an error while \(context): \(message)")
        }
    }
}

private extension FileManager {
    /// Puts `source` at `destination`. When something's already there (re-downloading
    /// a changed file), this swaps it in atomically instead of removing the old file
    /// and then moving the new one into place -- delete-then-move leaves a brief gap
    /// where `destination` doesn't exist at all, which a concurrent check like
    /// `MediaCache.isCached` running on another thread could catch mid-swap and
    /// wrongly report the file as not downloaded for a moment.
    func moveOrReplaceItem(at source: URL, to destination: URL) throws {
        try createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileExists(atPath: destination.path) {
            _ = try replaceItemAt(destination, withItemAt: source)
        } else {
            try moveItem(at: source, to: destination)
        }
    }
}
