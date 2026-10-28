import SwiftUI
import VisionKit
import AVFoundation
import PDFKit

struct ScanAndSendView: View {
    @Environment(\.openURL) private var openURL
    @State private var showingCamera = false
    @State private var requestingCamera = false
    @State private var pendingScan: VNDocumentCameraScan?
    @State private var completedScan: VNDocumentCameraScan?
    @State private var editor: ScannedDocument?
    @State private var message: String?
    @State private var canOpenSettings = false
    @State private var isPreparing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "doc.viewfinder")
                    .font(.largeTitle)
                    .foregroundStyle(AppStyle.accent)
                    .accessibilityHidden(true)
                Text("Scan & Send").font(.title2.bold())
                Text("Scan one or more pages. Review the corners and color filter, then mark up and share a print-ready PDF.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if isPreparing {
                    ProgressView("Preparing your document…")
                } else {
                    Button {
                        requestingCamera = true
                    } label: {
                        Label("Scan Document", systemImage: "camera")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(requestingCamera)
                }
                if let message {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if canOpenSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
                Text("Use Share to send your scan or save it to Files before closing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 500)
            .trainingCard()
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(AppStyle.background)
        .navigationTitle("Scan & Send")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: requestingCamera) {
            guard requestingCamera else { return }
            await openCamera()
            requestingCamera = false
        }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            // Wait until the camera is dismissed before presenting the editor.
            completedScan = pendingScan
            pendingScan = nil
        }) {
            DocumentScanner { result in
                switch result {
                case .success(let scan):
                    pendingScan = scan
                case .failure(let error):
                    message = error.localizedDescription
                }
                showingCamera = false
            }
            .ignoresSafeArea()
        }
        .task(id: completedScan != nil) {
            guard let scan = completedScan else { return }
            isPreparing = true
            defer {
                isPreparing = false
                completedScan = nil
            }
            do {
                let document = try await ScannedDocument.makePDF(pageCount: scan.pageCount) {
                    scan.imageOfPage(at: $0)
                }
                try Task.checkCancellation()
                editor = ScannedDocument(document: document)
            } catch is CancellationError {
                // Leaving the scanner screen cancels preparation.
            } catch {
                message = error.localizedDescription
            }
        }
        .fullScreenCover(item: $editor) { scan in
            FillableFormView(scannedDocument: scan.document, title: scan.title)
        }
    }

    @MainActor
    private func openCamera() async {
        message = nil
        canOpenSettings = false
        guard VNDocumentCameraViewController.isSupported else {
            message = AppLanguage.string("Document scanning is not available on this device.")
            return
        }
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard !Task.isCancelled else { return }
        switch status {
        case .authorized:
            showingCamera = true
        case .denied:
            message = AppLanguage.string("Allow camera access in Settings to scan documents.")
            canOpenSettings = true
        case .restricted:
            message = AppLanguage.string("Camera access is restricted on this device. Contact your administrator.")
        default:
            message = AppLanguage.string("Camera access is unavailable. Please try again.")
        }
    }
}

struct ScannedDocument: Identifiable {
    let id = UUID()
    let document: PDFDocument
    let title = "Scan " + Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))

    /// Process one page at a time and yield between pages to keep the interface responsive.
    @MainActor
    static func makePDF(pageCount: Int, image: (Int) -> UIImage) async throws -> PDFDocument {
        guard pageCount > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let document = PDFDocument()
        for index in 0..<pageCount {
            try Task.checkCancellation()
            try autoreleasepool {
                let page = try printablePage(image(index))
                document.insert(page, at: index)
            }
            await Task.yield()
        }
        return document
    }

    @MainActor
    private static func printablePage(_ image: UIImage) throws -> PDFPage {
        guard image.size.width > 0, image.size.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // VisionKit supplies the reviewed, perspective-corrected image, including
        // the user's color/B&W filter. Preserve those pixels when placing it on
        // US Letter paper; fit without stretching or clipping any document edges.
        let landscape = image.size.width > image.size.height
        let paper = CGRect(x: 0, y: 0, width: landscape ? 792 : 612, height: landscape ? 612 : 792)
        let printable = paper.insetBy(dx: 18, dy: 18)
        let scale = min(printable.width / image.size.width, printable.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let content = CGRect(x: paper.midX - size.width / 2, y: paper.midY - size.height / 2,
                             width: size.width, height: size.height)
        let data = UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.fill(paper)
            image.draw(in: content)
        }
        guard let page = PDFDocument(data: data)?.page(at: 0) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return page
    }
}

private struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: (Result<VNDocumentCameraScan?, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Result<VNDocumentCameraScan?, Error>) -> Void

        init(onFinish: @escaping (Result<VNDocumentCameraScan?, Error>) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            onFinish(.success(scan))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(.success(nil))
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onFinish(.failure(error))
        }
    }
}

#Preview {
    NavigationStack { ScanAndSendView() }
}
