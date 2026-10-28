import Foundation

// Codable so programs and their file lists survive relaunches via
// CatalogStore's on-disk snapshot -- without it, an offline launch would
// have no idea what's in Dropbox even though the files themselves are cached.
struct WalkthroughResource: Identifiable, Hashable, Codable {
    enum Kind: Hashable {
        case pdf
        case video
        case document
    }

    enum Location: Hashable, Codable {
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
        if ext == "pdf" { return .pdf }
        return Self.videoExtensions.contains(ext) ? .video : .document
    }

    /// Extensions treated as video. Internal (not private) so MediaCache can
    /// tell whether a raw Dropbox filename is a video without duplicating
    /// this list, e.g. to decide whether Wi-Fi-only downloads apply to it.
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
}

enum ProgramSource: Hashable, Codable {
    /// Files bundled in the app itself -- fully offline, but requires a rebuild to change.
    case local([WalkthroughResource])
    /// Files synced live from a Dropbox folder -- add a PDF or video there and it shows up
    /// next sync. `path` is relative to this app's dedicated Dropbox "App folder",
    /// e.g. "/Procore", or "" for the app folder's root.
    case dropbox(path: String)
}

struct Program: Identifiable, Hashable, Codable {
    /// Stable across syncs -- derived from the Dropbox path (or name, for `.local`
    /// programs) rather than a fresh UUID, so re-discovering the same folder doesn't
    /// reset its sync status or document list.
    let id: String
    let name: String
    let source: ProgramSource

    /// Only app-defined categories are localized; Dropbox names and identifiers stay intact.
    func displayName(locale: Locale) -> String {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "training resources": return AppLanguage.string("Training Resources", locale: locale)
        case "downloadable forms": return AppLanguage.string("Downloadable Forms", locale: locale)
        case "company newsletter": return AppLanguage.string("Company Newsletter", locale: locale)
        default: return name
        }
    }

    var isCompanyNewsletter: Bool {
        guard case .dropbox = source else { return false }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Company Newsletter") == .orderedSame
    }

    var isDownloadableForms: Bool {
        guard case .dropbox = source else { return false }
        // Both form libraries use the full-screen editor, including links from
        // search, pinned items, and viewing history.
        let folderName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["downloadable forms", "safety forms", "forms"].contains(folderName)
            || Self.isWeeklySafetyFolder(folderName)
    }

    /// Identify forms by their folder path too, so nested form folders and
    /// numbered/renamed categories never fall through to the read-only viewer.
    func opensInFormEditor(_ resource: WalkthroughResource) -> Bool {
        guard resource.kind == .pdf,
              case .dropbox(let file) = resource.location else { return false }
        if isDownloadableForms || Self.isFormFolder(name) { return true }
        return (file.pathLower as NSString).deletingLastPathComponent
            .split(separator: "/").contains { Self.isFormFolder(String($0)) }
    }

    private static func isFormFolder(_ name: String) -> Bool {
        let words = name.lowercased().split { !$0.isLetter }
        return words.contains("forms") || words.contains("form") || isWeeklySafetyFolder(name)
    }

    private static func isWeeklySafetyFolder(_ name: String) -> Bool {
        let words = name.lowercased().split { !$0.isLetter }
        return words.contains("weekly") && words.contains("safety")
            && (words.contains("topics") || words.contains("topic"))
    }

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
