import Foundation

/// A temporary, correctly named copy that Files can export without touching the cache.
struct FormExportFile: Identifiable, Sendable {
    let id: UUID
    let directory: URL
    let url: URL

    nonisolated static func prepare(source: URL, filename: String) throws -> FormExportFile {
        let id = UUID()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FormExport-\(id.uuidString)", isDirectory: true)
        let name = (filename as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
            return FormExportFile(id: id, directory: directory, url: destination)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// Saves exactly one copy in the chosen Files directory, keeping existing files intact.
    nonisolated static func finishExport(source: URL, destination: URL) throws -> URL {
        let hasAccess = destination.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { destination.stopAccessingSecurityScopedResource() }
        }
        let values = try destination.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        var coordinationError: NSError?
        var copyResult: Result<URL, Error>?
        NSFileCoordinator().coordinate(
            writingItemAt: destination,
            options: .forMerging,
            error: &coordinationError
        ) { directory in
            copyResult = Result {
                let filename = source.lastPathComponent
                let ext = source.pathExtension
                let base = ext.isEmpty ? filename : (filename as NSString).deletingPathExtension
                var number = 1
                while true {
                    let name = number == 1 ? filename
                        : base + " (\(number))" + (ext.isEmpty ? "" : ".\(ext)")
                    let candidate = directory.appendingPathComponent(name)
                    do {
                        // copyItem never overwrites: a concurrent collision gets another name.
                        try FileManager.default.copyItem(at: source, to: candidate)
                        return candidate
                    } catch let error as NSError where error.domain == NSCocoaErrorDomain
                        && error.code == NSFileWriteFileExistsError {
                        number += 1
                    }
                }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let copyResult else { throw CocoaError(.fileWriteUnknown) }
        return try copyResult.get()
    }

    nonisolated func removeTemporaryCopy() {
        try? FileManager.default.removeItem(at: directory)
    }
}
