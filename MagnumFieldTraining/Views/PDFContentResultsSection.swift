import SwiftUI

extension WalkthroughResource {
    var localSearchURL: URL? {
        switch location {
        case .bundled(let filename):
            let path = filename as NSString
            return Bundle.main.url(forResource: path.deletingPathExtension, withExtension: path.pathExtension)
        case .dropbox(let file):
            return MediaCache.shared.isCached(file) ? MediaCache.shared.localURL(for: file) : nil
        }
    }
}

struct LibrarySearchDocument: Equatable {
    let program: Program
    let resource: WalkthroughResource
}

struct PDFContentResultsSection: View {
    let query: String
    let documents: [LibrarySearchDocument]
    let cacheVersion: Int
    @State private var result = PDFContentSearchResult()
    @State private var isSearching = false
    @State private var completedRequest: Request?
    @State private var searchError: String?

    private struct Request: Equatable {
        let query: String
        let documents: [LibrarySearchDocument]
        let cacheVersion: Int
    }

    var body: some View {
        let request = Request(query: query, documents: documents, cacheVersion: cacheVersion)
        let current = completedRequest == request
        Section {
            Text("Content search covers downloaded PDFs. Download more files from their folders to include them. Scanned pages need a text layer to be searchable.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if isSearching || !current {
                ProgressView("Searching document contents…")
            } else {
                ForEach(result.matches) { match in
                    PDFContentResultRow(match: match, documents: documents)
                }
                if result.matches.isEmpty {
                    Text("No matching PDF content.").foregroundStyle(.secondary)
                }
                if result.isLimited {
                    Text("Showing the first 200 matching pages. Refine your search for more specific results.")
                        .font(.caption)
                }
                if result.unreadableCount > 0 {
                    Text("\(result.unreadableCount) PDFs couldn't be searched. Try downloading them again.")
                        .font(.caption)
                }
                if result.imageOnlyCount > 0 {
                    Text("\(result.imageOnlyCount) PDFs have no searchable text.")
                        .font(.caption)
                }
                if let searchError { Text(searchError).foregroundStyle(.red) }
            }
        } header: {
            Text("Inside Documents").textCase(nil)
        }
        .task(id: request) {
            isSearching = true
            searchError = nil
            do {
                try await Task.sleep(for: .milliseconds(300))
                let sources = documents.compactMap { item -> PDFSearchSource? in
                    guard let url = item.resource.localSearchURL else { return nil }
                    return PDFSearchSource(resourceID: item.resource.id, url: url)
                }
                let found = try await PDFContentSearch.search(query, sources: sources)
                try Task.checkCancellation()
                result = found
                completedRequest = request
                isSearching = false
            } catch is CancellationError {
                // A newer query owns the visible state.
            } catch {
                guard !Task.isCancelled else { return }
                result = PDFContentSearchResult()
                searchError = error.localizedDescription
                completedRequest = request
                isSearching = false
            }
        }
    }
}

private struct PDFContentResultRow: View {
    let match: PDFContentMatch
    let documents: [LibrarySearchDocument]
    @State private var showForm = false

    var body: some View {
        VStack(alignment: .leading) {
            if let item = documents.first(where: { $0.resource.id == match.resourceID }) {
                if item.program.opensInFormEditor(item.resource) {
                    Button { showForm = true } label: { label(item) }
                        .buttonStyle(.plain)
                        .fullScreenCover(isPresented: $showForm) {
                            FillableFormView(resource: item.resource, initialPageIndex: match.pageIndex)
                        }
                } else {
                    NavigationLink {
                        WalkthroughDetailView(resource: item.resource, initialPageIndex: match.pageIndex)
                    } label: {
                        label(item)
                    }
                }
            }
        }
    }

    private func label(_ item: LibrarySearchDocument) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.resource.title).font(.headline)
            Text("Page \(match.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
            Text(match.excerpt).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
        }
        .padding(.vertical, 4)
    }
}
