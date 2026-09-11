import Foundation

/// One folder's worth of walkthroughs within a program -- either the program's own
/// root folder, or a subfolder nested inside it (e.g. "Procore/Estimating"). Lets a
/// program organize a large set of PDFs/videos into folders instead of one long flat
/// list, mirroring whatever folder structure exists in that program's Dropbox folder.
/// Subfolders can nest to any depth; the app just renders whatever it finds.
struct WalkthroughFolder: Identifiable, Hashable {
    /// Stable Dropbox path (lowercased), e.g. "/procore/estimating" -- or the
    /// program's own id, for a `.local` program's single (subfolder-less) root.
    let id: String
    let name: String
    /// Files directly in this folder (not its subfolders).
    let resources: [WalkthroughResource]
    let subfolders: [WalkthroughFolder]

    /// This folder's own files plus every file in every folder nested inside it,
    /// flattened -- used wherever the app needs "everything in this program"
    /// regardless of how it's organized into folders (counts, caching, pinning).
    var allResources: [WalkthroughResource] {
        resources + subfolders.flatMap { $0.allResources }
    }
}

extension WalkthroughFolder {
    /// Builds a program's whole folder tree from one recursive Dropbox listing --
    /// `media` is every file found anywhere in the program's folder and `subfolders`
    /// is every folder found at any depth (see `DropboxService.FolderContents`).
    /// Grouping each by its parent path assembles the nesting in one pass, without
    /// a second round trip per folder.
    static func build(
        rootPath: String,
        rootID: String,
        rootName: String,
        media: [DropboxFileMetadata],
        subfolders: [DropboxService.FolderContents.Subfolder]
    ) -> WalkthroughFolder {
        func parentPath(of path: String) -> String {
            let parent = (path as NSString).deletingLastPathComponent
            return parent.isEmpty ? "/" : parent
        }

        var filesByParent: [String: [DropboxFileMetadata]] = [:]
        for file in media {
            filesByParent[parentPath(of: file.pathLower), default: []].append(file)
        }
        var subfoldersByParent: [String: [DropboxService.FolderContents.Subfolder]] = [:]
        for folder in subfolders {
            subfoldersByParent[parentPath(of: folder.path), default: []].append(folder)
        }

        func node(path: String, id: String, name: String) -> WalkthroughFolder {
            let resources = (filesByParent[path] ?? [])
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { WalkthroughResource(title: ($0.name as NSString).deletingPathExtension, location: .dropbox($0)) }
            let children = (subfoldersByParent[path] ?? [])
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { node(path: $0.path, id: $0.path, name: $0.name) }
            return WalkthroughFolder(id: id, name: name, resources: resources, subfolders: children)
        }

        let normalizedRoot = rootPath.isEmpty ? "/" : rootPath.lowercased()
        return node(path: normalizedRoot, id: rootID, name: rootName)
    }
}
