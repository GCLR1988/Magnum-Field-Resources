import Foundation

struct WalkthroughResource: Identifiable, Hashable {
    enum Kind: Hashable {
        case pdf
        case video
    }

    enum Location: Hashable {
        /// A file bundled directly inside the app (dropped into the PDFs folder in Xcode).
        case bundled(filename: String)
        /// A file that lives in Dropbox and is synced/cached locally.
        case dropbox(DropboxFileMetadata)
    }

    let title: String
    let location: Location

    var id: String { persistenceKey }

    /// Stable key used for pin storage and local cache lookups.
    var persistenceKey: String {
        switch location {
        case .bundled(let filename):
            return "bundled:\(filename)"
        case .dropbox(let file):
            return "dropbox:\(file.id)"
        }
    }

    /// Whether this is a PDF or a video, inferred from the file's extension.
    var kind: Kind {
        let name: String
        switch location {
        case .bundled(let filename): name = filename
        case .dropbox(let file): name = file.name
        }
        let ext = (name as NSString).pathExtension.lowercased()
        return Self.videoExtensions.contains(ext) ? .video : .pdf
    }

    /// Extensions treated as video. Internal (not private) so MediaCache can
    /// tell whether a raw Dropbox filename is a video without duplicating
    /// this list, e.g. to decide whether Wi-Fi-only downloads apply to it.
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
}

enum ProgramSource: Hashable {
    /// Files bundled in the app itself -- fully offline, but requires a rebuild to change.
    case local([WalkthroughResource])
    /// Files synced live from a Dropbox folder -- add a PDF or video there and it shows up
    /// next sync. `path` is relative to this app's dedicated Dropbox "App folder",
    /// e.g. "/Procore", or "" for the app folder's root.
    case dropbox(path: String)
}

struct Program: Identifiable, Hashable {
    /// Stable across syncs -- derived from the Dropbox path (or name, for `.local`
    /// programs) rather than a fresh UUID, so re-discovering the same folder doesn't
    /// reset its sync status or document list.
    let id: String
    let name: String
    let source: ProgramSource

    init(name: String, source: ProgramSource) {
        self.name = name
        self.source = source
        switch source {
        case .dropbox(let path):
            self.id = "dropbox:\(path)"
        case .local:
            self.id = "local:\(name)"
        }
    }
}
