import SwiftUI
import PDFKit

/// Thin SwiftUI wrapper around PDFKit's PDFView so we get a fast,
/// native, pinch-to-zoom PDF viewer for free. The PDFView instance is
/// owned by the parent (WalkthroughDetailView) rather than created here,
/// so the parent can also drive it directly for text search and page
/// navigation, and share it with a PDFThumbnailBar.
struct PDFKitRepresentedView: UIViewRepresentable {
    let document: PDFDocument
    let pdfView: PDFView

    func makeUIView(context: Context) -> PDFView {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }
    }
}
