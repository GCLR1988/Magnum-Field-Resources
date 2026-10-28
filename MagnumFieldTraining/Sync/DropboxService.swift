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
        var logosByFolder: [String: DropboxFileMetadata] = [:]

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
        let server_modified: String?

        private enum CodingKeys: String, CodingKey {
            case tag = ".tag"
            case id, name, path_lower, rev, server_modified
        }
    }

    /// Lists everything under a program folder -- its own PDFs/videos, any nested
    /// inside subfolders (so a program can organize its walkthroughs into folders
    /// like "Estimating" or "Scheduling"), those subfolders themselves, and the
    /// program's logo if one is present directly in its root -- a file named
    /// "logo.png"/"logo.jpg"/"logo.jpeg" (case-insensitive), used as that program's
    /// tile icon instead of the generic folder icon. `path` is relative to the app's
    /// dedicated Dropbox folder, e.g. "/Procore".
    static func listFolderContents(path: String, includeAllFiles: Bool = false) async throws -> FolderContents {
        let allEntries = try await listAllEntries(path: path, recursive: true)
        let files = allEntries.compactMap { entry -> DropboxFileMetadata? in
            guard entry.tag == "file",
                  let id = entry.id, let name = entry.name,
                  let pathLower = entry.path_lower, let rev = entry.rev else { return nil }
            return DropboxFileMetadata(id: id, name: name, pathLower: pathLower, rev: rev, serverModified: entry.server_modified)
        }

        let rootLower = path.isEmpty ? "/" : path.lowercased()
        let images = files.filter { logoExtensions.contains(($0.name as NSString).pathExtension.lowercased()) }
        let imagesByFolder = Dictionary(grouping: images) {
            ($0.pathLower as NSString).deletingLastPathComponent
        }
        var logosByFolder: [String: DropboxFileMetadata] = [:]
        for (folder, candidates) in imagesByFolder {
            let sorted = candidates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if let namedLogo = sorted.first(where: { isLogoFile($0.name) }) {
                logosByFolder[folder] = namedLogo
            } else if !includeAllFiles, sorted.count == 1 {
                // Training folders may contain one supplied picture without a "logo" filename.
                logosByFolder[folder] = sorted.first
            }
        }
        let logo = logosByFolder[rootLower]

        let subfolders = allEntries.compactMap { entry -> FolderContents.Subfolder? in
            guard entry.tag == "folder", let name = entry.name, let pathLower = entry.path_lower else { return nil }
            return FolderContents.Subfolder(path: pathLower, name: name)
        }

        // Artwork is decoration, including inside nested folders.
        let artworkIDs = Set(logosByFolder.values.map(\.id))
        let media = files.filter {
            !artworkIDs.contains($0.id) && (includeAllFiles || isSupportedMediaFile($0.name))
        }
        return FolderContents(media: media, logo: logo, subfolders: subfolders, logosByFolder: logosByFolder)
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

    /// Spreadsheet resources can live at the app root or within a resource folder.
    static func listResourceSpreadsheets() async throws -> [DropboxFileMetadata] {
        let entries = try await listAllEntries(path: "", recursive: true)
        let names: Set<String> = ["company directory.xlsx", "employee directory.xlsx", "useful links.xlsx"]
        return entries.compactMap { entry in
            guard entry.tag == "file", let name = entry.name, names.contains(name.lowercased()),
                  let id = entry.id, let path = entry.path_lower, let rev = entry.rev else { return nil }
            return DropboxFileMetadata(id: id, name: name, pathLower: path, rev: rev, serverModified: entry.server_modified)
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
    static func download(_ file: DropboxFileMetadata, to destination: URL, allowCellular: Bool = true) async throws {
        let token = try await DropboxAuthService.shared.accessToken()
        guard let url = URL(string: "https://content.dropboxapi.com/2/files/download") else {
            throw DropboxError.requestFailed("Invalid Dropbox request URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.allowsCellularAccess = allowCellular
        let argJSON = try JSONEncoder().encode(["path": "rev:\(file.rev)"])
        request.setValue(String(data: argJSON, encoding: .utf8), forHTTPHeaderField: "Dropbox-API-Arg")

        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                let (tempURL, urlResponse) = try await URLSession.shared.download(for: request)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                guard let http = urlResponse as? HTTPURLResponse else {
                    throw DropboxError.requestFailed("No response while downloading \(file.name).")
                }
                guard http.statusCode == 200 else {
                    if http.statusCode == 429 || (500...599).contains(http.statusCode) {
                        throw DownloadRetryPolicy.TemporaryHTTPError(
                            status: http.statusCode,
                            retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                        )
                    }
                    throw DropboxError.requestFailed("Couldn't download \(file.name) (HTTP \(http.statusCode)).")
                }
                try Task.checkCancellation()
                try FileManager.default.moveOrReplaceItem(at: tempURL, to: destination)
                return
            } catch {
                guard let delay = DownloadRetryPolicy.delay(for: error, attempt: attempt) else { throw error }
                try await Task.sleep(for: .seconds(delay))
            }
        }
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
