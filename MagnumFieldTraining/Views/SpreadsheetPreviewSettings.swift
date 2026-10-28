#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

/// Lets developers test an attached workbook without changing live credentials.
struct SpreadsheetPreviewSettings: View {
    @State private var resources = SpreadsheetStore.shared
    @State private var showImporter = false
    @State private var directory = true
    @State private var importError: String?
    @State private var showError = false

    var body: some View {
        Section {
            Button("Preview Directory Spreadsheet") {
                directory = true
                showImporter = true
            }
            Button("Preview Useful Links Spreadsheet") {
                directory = false
                showImporter = true
            }
            if resources.isLocalPreview {
                Button("End Spreadsheet Preview") {
                    Task { await resources.endPreview() }
                }
            }
        } header: {
            Text("Spreadsheet Testing")
        } footer: {
            Text("Preview Excel files from Files. Previews last until the app closes and do not change Dropbox.")
        }
        .disabled(resources.isSyncing)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data]) { result in
            Task {
                do {
                    let url = try result.get()
                    try await resources.preview(url: url, directory: directory)
                } catch {
                    importError = error.localizedDescription
                    showError = true
                }
            }
        }
        .alert("Couldn't Read Spreadsheet", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? AppLanguage.string("Please choose an Excel workbook."))
        }
    }
}
#endif
