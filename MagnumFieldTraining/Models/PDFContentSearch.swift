import Foundation
import PDFKit

nonisolated struct PDFSearchSource: Sendable, Equatable {
    let resourceID: String
    let url: URL
}

nonisolated struct PDFContentMatch: Identifiable, Sendable, Equatable {
    let resourceID: String
    let pageIndex: Int
    let excerpt: String
    var id: String { "\(resourceID):\(pageIndex)" }
}

nonisolated struct PDFContentSearchResult: Sendable {
    var matches: [PDFContentMatch] = []
    var unreadableCount = 0
    var imageOnlyCount = 0
    var isLimited = false
}

enum PDFContentSearch {
    /// PDFKit objects are created and consumed on this executor, never shared with
    /// an onscreen document. Check cancellation between pages as the query changes.
    @concurrent
    nonisolated static func search(_ query: String, sources: [PDFSearchSource]) async throws -> PDFContentSearchResult {
        try Task.checkCancellation()
        var result = PDFContentSearchResult()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return result }
        for source in sources {
            try Task.checkCancellation()
            guard let document = PDFDocument(url: source.url), !document.isLocked, document.pageCount > 0 else {
                result.unreadableCount += 1
                continue
            }
            var hasText = false
            for pageIndex in 0..<document.pageCount {
                try Task.checkCancellation()
                let text = document.page(at: pageIndex)?.string ?? ""
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hasText = true }
                guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                let start = text.index(range.lowerBound, offsetBy: -70, limitedBy: text.startIndex) ?? text.startIndex
                let end = text.index(range.upperBound, offsetBy: 130, limitedBy: text.endIndex) ?? text.endIndex
                let excerpt = (start > text.startIndex ? "…" : "")
                    + text[start..<end].split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                    + (end < text.endIndex ? "…" : "")
                result.matches.append(PDFContentMatch(resourceID: source.resourceID, pageIndex: pageIndex, excerpt: excerpt))
                if result.matches.count >= 200 {
                    result.isLimited = true
                    return result
                }
            }
            if !hasText { result.imageOnlyCount += 1 }
        }
        return result
    }
}
