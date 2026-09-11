import SwiftUI
import PDFKit

/// Thin horizontal strip of page thumbnails bound to a shared PDFView, so a
/// foreman can jump straight to the right page of a long walkthrough
/// instead of scrolling through it page by page.
struct PDFThumbnailBar: UIViewRepresentable {
    let pdfView: PDFView

    func makeUIView(context: Context) -> PDFThumbnailView {
        let thumbnailView = PDFThumbnailView()
        thumbnailView.pdfView = pdfView
        thumbnailView.layoutMode = .horizontal
        thumbnailView.thumbnailSize = CGSize(width: 44, height: 56)
        thumbnailView.backgroundColor = .clear
        return thumbnailView
    }

    func updateUIView(_ uiView: PDFThumbnailView, context: Context) {
        if uiView.pdfView !== pdfView {
            uiView.pdfView = pdfView
        }
    }
}
