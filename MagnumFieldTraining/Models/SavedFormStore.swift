import Foundation
import Observation
import PDFKit

struct SavedForm: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case draft
        case template
    }

    let id: UUID
    var name: String
    var kind: Kind
    var modifiedAt: Date
    var wasExplicitlyAdded: Bool?

    var belongsToLibrary: Bool { wasExplicitlyAdded ?? (kind == .template) }
}

/// Each atomic file contains both metadata and the editable PDF, so a failed
/// save cannot leave a new index pointing to an incomplete document.
@MainActor
@Observable
final class SavedFormStore {
    static let shared = SavedFormStore()
    private(set) var drafts: [SavedForm] = []
    private(set) var templates: [SavedForm] = []
    private(set) var earlierForms: [SavedForm] = []

    private var allForms: [SavedForm] { drafts + templates + earlierForms }
    private(set) var loadError: String?
    private let directory: URL

    private struct Archive: Codable {
        let form: SavedForm
        let pdf: Data
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appendingPathComponent("SavedForms", isDirectory: true)
        reload()
    }

    func reload() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            var forms: [SavedForm] = []
            var unreadable = false
            for url in urls where url.pathExtension == "savedform" {
                do {
                    let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
                    forms.append(archive.form)
                } catch {
                    unreadable = true
                }
            }
            update(forms)
            loadError = unreadable ? AppLanguage.string("Some saved forms could not be read. Their files have been kept. Try again after unlocking your device.") : nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func document(for form: SavedForm) throws -> PDFDocument {
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL(form.id)))
        guard let document = PDFDocument(data: archive.pdf), !document.isLocked, document.pageCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return document
    }

    @discardableResult
    func save(document: PDFDocument, id: UUID, name: String, kind: SavedForm.Kind) throws -> SavedForm {
        guard let data = document.dataRepresentation() else { throw CocoaError(.fileWriteUnknown) }
        return try save(data: data, id: id, name: name, kind: kind)
    }

    @discardableResult
    private func save(data: Data, id: UUID, name: String, kind: SavedForm.Kind, wasExplicitlyAdded: Bool? = true) throws -> SavedForm {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let form = SavedForm(id: id, name: trimmed, kind: kind, modifiedAt: Date(), wasExplicitlyAdded: wasExplicitlyAdded)
        let data = try JSONEncoder().encode(Archive(form: form, pdf: data))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: fileURL(id), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: fileURL(id), options: .atomic)
        #endif
        update(allForms.filter { $0.id != id } + [form])
        return form
    }

    func rename(_ form: SavedForm, to name: String) throws {
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL(form.id)))
        try save(data: archive.pdf, id: form.id, name: name, kind: form.kind, wasExplicitlyAdded: archive.form.wasExplicitlyAdded)
    }

    func delete(_ form: SavedForm) throws {
        try FileManager.default.removeItem(at: fileURL(form.id))
        update(allForms.filter { $0.id != form.id })
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("savedform")
    }

    private func update(_ forms: [SavedForm]) {
        let sorted = forms.sorted { $0.modifiedAt > $1.modifiedAt }
        drafts = sorted.filter { $0.kind == .draft && $0.belongsToLibrary }
        templates = sorted.filter { $0.kind == .template && $0.belongsToLibrary }
        earlierForms = sorted.filter { !$0.belongsToLibrary }
    }
}
