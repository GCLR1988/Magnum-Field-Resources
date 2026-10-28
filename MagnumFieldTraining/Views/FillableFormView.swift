import SwiftUI
import PDFKit

/// A fresh, memory-only document for each presentation. Never writes to the cached template.
struct FillableFormView: View {
    private let resource: WalkthroughResource?
    private let title: String

    init(resource: WalkthroughResource) {
        self.resource = resource
        title = resource.title
    }

    init(scannedDocument: PDFDocument, title: String) {
        resource = nil
        self.title = title
        _document = State(initialValue: scannedDocument)
    }
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

    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    EditableFormPDF(document: document, pdfView: pdfView, isDrawing: isDrawing, tool: drawingTool) {
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
                        isClosed = true
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
                        isDrawing.toggle()
                    } label: {
                        Label(isDrawing ? "Done Markup" : "Markup",
                              systemImage: isDrawing ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                    }
                    .accessibilityValue(isDrawing ? "On" : "Off")
                    .disabled(document == nil || export != nil)
                    Button {
                        share()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(document == nil || export != nil)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isDrawing {
                    FormMarkupToolbar(tool: $drawingTool, undoCount: strokeCount, redoCount: redoCount,
                                      undo: { pdfView.undoStroke() }, redo: { pdfView.redoStroke() })
                }
            }
            .task(id: loadAttempt) { await load() }
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
        guard !isClosed, document == nil, let resource else { return }
        loadError = nil
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

    @MainActor
    private func share() {
        // Commit the active field before serializing, including its last typed characters.
        pdfView.endEditing(true)
        pdfView.finishStroke()
        isDrawing = false
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
    let onHistoryChange: (Int, Int) -> Void

    func makeUIView(context: Context) -> SigningPDFView {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document
        pdfView.onHistoryChange = onHistoryChange
        pdfView.drawingTool = tool
        pdfView.drawingEnabled = isDrawing
        return pdfView
    }

    func updateUIView(_ uiView: SigningPDFView, context: Context) {
        uiView.onHistoryChange = onHistoryChange
        uiView.drawingTool = tool
        uiView.drawingEnabled = isDrawing
        if uiView.document !== document {
            uiView.document = document
        }
    }

    static func dismantleUIView(_ uiView: SigningPDFView, coordinator: ()) {
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


