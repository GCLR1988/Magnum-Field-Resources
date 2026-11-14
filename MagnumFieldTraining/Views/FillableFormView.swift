import SwiftUI
import PDFKit

/// Works on a private editable copy, saved separately from the downloaded library.
struct FillableFormView: View {
    private let resource: WalkthroughResource?
    private let title: String
    private var savedForm: SavedForm?
    private var editingTemplate = false
    private var initialPageIndex: Int?

    init(resource: WalkthroughResource, initialPageIndex: Int? = nil) {
        self.initialPageIndex = initialPageIndex
        self.resource = resource
        title = resource.title
    }

    init(scannedDocument: PDFDocument, title: String) {
        resource = nil
        self.title = title
        _document = State(initialValue: scannedDocument)
    }
    init(savedForm: SavedForm, editingTemplate: Bool = false) {
        resource = nil
        title = savedForm.name
        self.savedForm = savedForm
        self.editingTemplate = editingTemplate
        _isAddedToMyForms = State(initialValue: savedForm.belongsToLibrary && (savedForm.kind == .draft || editingTemplate))
        _draftID = State(initialValue: savedForm.kind == .template && !editingTemplate ? UUID() : savedForm.id)
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var draftID = UUID()
    @State private var isAddedToMyForms = false
    @State private var didSaveTemplate = false
    @State private var saveError: String?
    @State private var savedAt: Date?
    @State private var templateName = ""
    @State private var showTemplateName = false
    @State private var showSaveOptions = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var lastSavedData: Data?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalogStore: CatalogStore
    @State private var document: PDFDocument?
    @State private var pdfView = SigningPDFView()
    @State private var isDrawing = false
    @State private var strokeCount = 0
    @State private var redoCount = 0
    @State private var drawingTool: FormDrawingTool = .pen
    @State private var loadError: String?
    @State private var loadAttempt = 0
    @State private var isClosed = false
    @State private var shareError: String?
    @State private var pendingShareError: String?
    @State private var export: FilledFormExport?
    @State private var showAssistant = false
    @State private var reviewing = false
    @State private var startsWithDates = false
    @State private var shareAfterReview = false
    @State private var fieldToLocate: FormField?

    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    EditableFormPDF(document: document, pdfView: pdfView, isDrawing: isDrawing, tool: drawingTool, initialPageIndex: initialPageIndex, onChange: scheduleAutosave) {
                        strokeCount = $0
                        redoCount = $1
                    }
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't open form", systemImage: "doc.badge.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try Again") {
                            loadAttempt += 1
                        }
                    }
                } else {
                    ResourceLoadingView(title: "Opening form…")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        guard document == nil || saveDraft(commitEditing: true) else { return }
                        isClosed = true
                        autosaveTask?.cancel()
                        pdfView.endEditing(true)
                        pdfView.clearDrawingHistory()
                        pdfView.document = nil
                        document = nil
                        export = nil
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        pdfView.endEditing(true)
                        pdfView.finishStroke()
                        isDrawing = false
                        reviewing = false
                        startsWithDates = false
                        showAssistant = true
                    } label: {
                        Label("Form Fields", systemImage: "list.bullet.rectangle")
                    }
                    .disabled(document == nil || export != nil)
                    Button {
                        pdfView.endEditing(true)
                        isDrawing.toggle()
                    } label: {
                        Label(isDrawing ? "Done Markup" : "Markup",
                              systemImage: isDrawing ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                    }
                    .accessibilityValue(isDrawing ? "On" : "Off")
                    .disabled(document == nil || export != nil)
                    Button {
                        pdfView.endEditing(true)
                        pdfView.finishStroke()
                        isDrawing = false
                        // Scans (including saved scans) have no fillable fields to review.
                        if let document, FormFieldSupport.fields(in: document).isEmpty {
                            share()
                        } else {
                            reviewing = true
                            startsWithDates = false
                            showAssistant = true
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(document == nil || export != nil)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if savedForm?.kind == .template, let document,
                       FormFieldSupport.fields(in: document).contains(where: \.isDate) {
                        Button("Use Today’s Date", systemImage: "calendar") {
                            pdfView.endEditing(true)
                            pdfView.finishStroke()
                            isDrawing = false
                            reviewing = false
                            startsWithDates = true
                            showAssistant = true
                        }
                        .padding(.top, 8)
                    }
                    if let saveError {
                        Text("Couldn't save: \(saveError)")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(8)
                    } else if savedAt != nil {
                        Text(editingTemplate || didSaveTemplate ? "Template saved on this device" : "Form saved on this device")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    } else if !isAddedToMyForms, document != nil {
                        Text("Add this form to keep your entries after closing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    Button {
                        pdfView.endEditing(true)
                        pdfView.finishStroke()
                        showSaveOptions = true
                    } label: {
                        Label(isAddedToMyForms ? "Save to My Forms & Templates" : "Add to My Forms & Templates", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppStyle.accent)
                    .disabled(document == nil || export != nil)
                    .padding(.horizontal, AppStyle.inset)
                    .padding(.bottom, 8)
                    if isDrawing {
                        FormMarkupToolbar(tool: $drawingTool, undoCount: strokeCount, redoCount: redoCount,
                                          undo: { pdfView.undoStroke() }, redo: { pdfView.redoStroke() })
                    }
                }
            }
            .interactiveDismissDisabled()
            .task(id: loadAttempt) {
                await load()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active, !isClosed { _ = saveDraft(commitEditing: true) }
            }
            .onDisappear {
                autosaveTask?.cancel()
                if !isClosed { _ = saveDraft(commitEditing: true) }
            }
            .confirmationDialog("Save to My Forms & Templates", isPresented: $showSaveOptions, titleVisibility: .visible) {
                Button(editingTemplate ? "Save Template Changes" : "Save Form") {
                    _ = saveDraft(commitEditing: true, explicitlyAdd: true)
                }
                Button("Save as Reusable Template") {
                    templateName = title
                    showTemplateName = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved forms keep your entries and markup. Reusable templates keep a filled-in starting point for new forms.")
            }
            .alert("Save as Template", isPresented: $showTemplateName) {
                TextField("Template name", text: $templateName)
                Button("Save Template") { saveTemplate() }
                    .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Keep your usual information for next time. Using this template creates a separate draft. Review dates and signatures before sending.")
            }
            .sheet(isPresented: $showAssistant, onDismiss: {
                if let field = fieldToLocate, let page = field.annotation.page {
                    pdfView.go(to: field.annotation.bounds, on: page)
                    fieldToLocate = nil
                }
                if shareAfterReview {
                    shareAfterReview = false
                    share()
                }
            }) {
                if let document {
                    FormAssistantView(document: document, reviewing: reviewing, startsWithDates: startsWithDates, onChange: {
                        pdfView.setNeedsDisplay()
                        scheduleAutosave()
                    }, onLocate: { fieldToLocate = $0 }, onShare: { shareAfterReview = true })
                }
            }
            .sheet(item: $export, onDismiss: {
                // Present errors only after the share sheet has finished dismissing.
                shareError = pendingShareError
                pendingShareError = nil
            }) { prepared in
                FilledFormShareSheet(url: prepared.url) { error in
                    pendingShareError = error?.localizedDescription
                    export = nil
                }
            }
            .alert("Couldn't share form", isPresented: Binding(
                get: { shareError != nil },
                set: { if !$0 { shareError = nil } }
            )) {
                Button("OK", role: .cancel) { shareError = nil }
            } message: {
                Text(shareError ?? "")
            }
        }
    }

    @MainActor
    private func load() async {
        guard !isClosed, document == nil else { return }
        loadError = nil
        if let savedForm {
            do {
                document = try SavedFormStore.shared.document(for: savedForm)
                if savedForm.belongsToLibrary && savedForm.kind == .draft {
                    RecentStore.shared.record("saved-form:\(savedForm.id.uuidString)")
                }
            }
            catch { loadError = error.localizedDescription }
            return
        }
        guard let resource else { return }
        do {
            guard case .dropbox(let file) = resource.location else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            let neededDownload = await MediaCache.shared.needsDownload(file)
            let url = try await MediaCache.shared.availableURL(for: file)
            try Task.checkCancellation()
            let freshDocument: PDFDocument
            do {
                freshDocument = try await FormDocumentLoader.load(from: url)
            } catch let error as CocoaError where error.code == .fileReadCorruptFile {
                await MediaCache.shared.invalidateCachedRevision(for: file)
                throw error
            }
            try Task.checkCancellation()
            guard !isClosed else { return }
            document = freshDocument
            SeenStore.shared.markSeen([resource.persistenceKey])
            RecentStore.shared.record(resource.persistenceKey)
            if neededDownload { await catalogStore.noteFileCached() }
        } catch is CancellationError {
            return
        } catch {
            guard !isClosed, !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
    }

    private func scheduleAutosave() {
        guard !isClosed, isAddedToMyForms else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled, !isClosed else { return }
            _ = saveDraft(commitEditing: false)
        }
    }

    @discardableResult
    private func saveDraft(commitEditing: Bool, explicitlyAdd: Bool = false) -> Bool {
        // Browsing, sharing, and closing a library form must never add it implicitly.
        guard isAddedToMyForms || explicitlyAdd else { return true }
        guard let document, !isClosed else { return false }
        if commitEditing {
            pdfView.endEditing(true)
            pdfView.finishStroke()
        }
        do {
            guard let data = document.dataRepresentation() else { throw CocoaError(.fileWriteUnknown) }
            if !isAddedToMyForms || lastSavedData != data {
                try SavedFormStore.shared.save(document: document, id: draftID, name: title,
                                               kind: editingTemplate ? .template : .draft)
                if !editingTemplate && !isAddedToMyForms {
                    RecentStore.shared.record("saved-form:\(draftID.uuidString)")
                }
                isAddedToMyForms = true
                didSaveTemplate = false
                lastSavedData = data
                savedAt = Date()
            }
            saveError = nil
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    private func saveTemplate() {
        pdfView.endEditing(true)
        pdfView.finishStroke()
        guard let document else { return }
        do {
            try SavedFormStore.shared.save(document: document, id: UUID(), name: templateName, kind: .template)
            didSaveTemplate = true
            savedAt = Date()
            saveError = nil
        } catch { saveError = error.localizedDescription }
    }

    @MainActor
    private func share() {
        // Commit the active field before serializing, including its last typed characters.
        pdfView.endEditing(true)
        pdfView.finishStroke()
        isDrawing = false
        _ = saveDraft(commitEditing: true)
        guard let document else { return }
        do {
            let filename: String
            if let resource, case .dropbox(let file) = resource.location {
                filename = file.name
            } else {
                filename = title + ".pdf"
            }
            export = try FilledFormExport(document: document, filename: filename)
        } catch {
            shareError = error.localizedDescription
        }
    }
}

/// Build a private editable document away from the UI executor. Ownership moves
/// to the caller only after preparation ends; the background work never retains it.
enum FormDocumentLoader {
    @concurrent
    nonisolated static func load(from url: URL) async throws -> sending PDFDocument {
        try Task.checkCancellation()
        let data = try Data(contentsOf: url)
        try Task.checkCancellation()
        guard let document = PDFDocument(data: data), !document.isLocked,
              document.pageCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Resolve the first page's fields before PDFView presents the editor.
        _ = document.page(at: 0)?.annotations
        try Task.checkCancellation()
        return document
    }
}

private struct EditableFormPDF: UIViewRepresentable {
    let document: PDFDocument
    let pdfView: SigningPDFView
    let isDrawing: Bool
    let tool: FormDrawingTool
    let initialPageIndex: Int?
    let onChange: () -> Void
    let onHistoryChange: (Int, Int) -> Void

    func makeUIView(context: Context) -> SigningPDFView {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document
        pdfView.restoreSavedInk()
        if let initialPageIndex, let page = document.page(at: initialPageIndex) {
            pdfView.go(to: page)
        }
        pdfView.onDocumentChange = onChange
        pdfView.onHistoryChange = onHistoryChange
        pdfView.drawingTool = tool
        pdfView.drawingEnabled = isDrawing
        return pdfView
    }

    func updateUIView(_ uiView: SigningPDFView, context: Context) {
        uiView.onDocumentChange = onChange
        uiView.onHistoryChange = onHistoryChange
        uiView.drawingTool = tool
        uiView.drawingEnabled = isDrawing
        if uiView.document !== document {
            uiView.document = document
        }
    }

    static func dismantleUIView(_ uiView: SigningPDFView, coordinator: ()) {
        uiView.endEditing(true)
        uiView.finishStroke()
        uiView.onDocumentChange = nil
        uiView.onHistoryChange = nil
        uiView.clearDrawingHistory()
        uiView.endEditing(true)
        uiView.document = nil
    }
}

/// Lives only while the system share sheet needs the completed PDF.
final class FilledFormExport: Identifiable {
    let id = UUID()
    let directory: URL
    let url: URL

    init(document: PDFDocument, filename: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilledForm-\(UUID().uuidString)", isDirectory: true)
        let name = (filename as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        url = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let data = document.dataRepresentation() else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct FilledFormShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: (Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in
            onFinish(error)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct FormMarkupToolbar: View {
    @Binding var tool: FormDrawingTool
    let undoCount: Int
    let redoCount: Int
    let undo: () -> Void
    let redo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button("Pen", systemImage: "pencil.tip") { tool = .pen }
                .tint(tool == .pen ? Color.accentColor : .secondary)
                .accessibilityValue(tool == .pen ? "Selected" : "")
            Button("Eraser", systemImage: "eraser") { tool = .eraser }
                .tint(tool == .eraser ? Color.accentColor : .secondary)
                .accessibilityValue(tool == .eraser ? "Selected" : "")
            Spacer()
            Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                .disabled(undoCount == 0)
            Button("Redo", systemImage: "arrow.uturn.forward", action: redo)
                .disabled(redoCount == 0)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(FormToolButtonStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.regularMaterial)
    }
}

private struct FormToolButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.tint)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.3)
    }
}


