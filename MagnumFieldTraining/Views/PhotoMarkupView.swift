import SwiftUI
import PhotosUI
import AVFoundation

/// Photos are edited in a temporary workspace; the source photo is never changed.
struct PhotoMarkupView: View {
    @Environment(\.openURL) private var openURL
    @State private var selection: PhotosPickerItem?
    @State private var requestingCamera = false
    @State private var showingCamera = false
    @State private var pendingPhoto: UIImage?
    @State private var editor: MarkupPhoto?
    @State private var activePhoto: MarkupPhoto?
    @State private var isPreparing = false
    @State private var message: String?
    @State private var canOpenSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "photo.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(AppStyle.accent)
                    .accessibilityHidden(true)
                Text("Photo Markup").font(.title2.bold())
                Text("Take or choose a photo. Draw, add pins and shapes, or create a before-and-after image.")
                    .multilineTextAlignment(.center)
                Text("All your photo tools are on one page. Tap Share when you’re ready to send.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if isPreparing {
                    ProgressView("Preparing photo…")
                }
                Button {
                    requestingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPreparing || requestingCamera)
                PhotosPicker(selection: $selection, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .disabled(isPreparing || requestingCamera)
                if let message {
                    Text(message).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if canOpenSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
                Text("Share before closing. Your original photo stays unchanged.")
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
        .navigationTitle("Photo Markup")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selection) {
            guard let selection else { return }
            isPreparing = true
            message = nil
            defer {
                isPreparing = false
                self.selection = nil
            }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try Task.checkCancellation()
                try prepare(image)
            } catch is CancellationError {
                // A new selection or leaving the screen cancels the import.
            } catch {
                message = AppLanguage.string("Couldn't open this photo. Please choose another photo or try again.")
            }
        }
        .task(id: requestingCamera) {
            guard requestingCamera else { return }
            defer { requestingCamera = false }
            message = nil
            canOpenSettings = false
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                message = AppLanguage.string("The camera is not available on this device. Choose a photo instead.")
                return
            }
            var status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                status = AVCaptureDevice.authorizationStatus(for: .video)
            }
            guard !Task.isCancelled else { return }
            if status == .authorized {
                showingCamera = true
            } else {
                message = AppLanguage.string("Camera access is unavailable. You can choose a photo instead.")
                canOpenSettings = status == .denied
            }
        }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            guard let photo = pendingPhoto else { return }
            pendingPhoto = nil
            do {
                try prepare(photo)
            } catch {
                message = AppLanguage.string("Couldn't prepare this photo. Please try again.")
            }
        }) {
            MarkupCamera { photo in
                pendingPhoto = photo
                showingCamera = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $editor, onDismiss: {
            activePhoto?.remove()
            activePhoto = nil
        }) { photo in
            PhotoMarkupWorkspace(photo: photo)
        }
    }

    private func prepare(_ image: UIImage) throws {
        let photo = try MarkupPhoto(image: image)
        activePhoto = photo
        editor = photo
    }
}

private struct PhotoMarkupWorkspace: View {
    @Environment(\.dismiss) private var dismiss
    let photo: MarkupPhoto
    @State private var share: MarkupPhoto?
    @State private var activePreview: MarkupPhoto?
    @State private var error: String?

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: photo.url.path) {
                PhotoFieldToolsView(source: image, isSharing: share != nil) { result in
                    do {
                        let rendered = try MarkupPhoto(image: result)
                        activePreview = rendered
                        share = rendered
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            } else {
                NavigationStack {
                    ContentUnavailableView("Photo unavailable", systemImage: "photo",
                                           description: Text("Close this editor and choose the photo again."))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { dismiss() }
                            }
                        }
                }
            }
        }
        .sheet(item: $share, onDismiss: {
            activePreview?.remove()
            activePreview = nil
        }) { rendered in
            PhotoShareSheet(url: rendered.url)
        }
        .alert("Couldn't prepare photo", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }
}

private struct MarkupPhoto: Identifiable {
    let id = UUID()
    let directory: URL
    let url: URL

    @MainActor
    init(image: UIImage) throws {
        guard image.size.width > 0, image.size.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoMarkup-" + UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("Marked Up Photo.jpg")
        // Normalize camera orientation and bound memory use in the markup editor.
        let scale = min(1, 3000 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.95) { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct PhotoShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct MarkupCamera: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        // Custom capture delivers the photo directly, without the system review screen.
        controller.showsCameraControls = false
        let overlay = UIView(frame: controller.view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let controls = UIStackView()
        controls.axis = .horizontal
        controls.distribution = .equalSpacing
        controls.alignment = .center
        controls.spacing = 24
        controls.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(controls)

        let cancel = UIButton(type: .system)
        cancel.setTitle(AppLanguage.string("Cancel"), for: .normal)
        cancel.addAction(UIAction { [weak coordinator = context.coordinator] _ in
            coordinator?.finish(nil)
        }, for: .touchUpInside)

        let capture = UIButton(type: .system)
        capture.setImage(UIImage(systemName: "circle.inset.filled",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 60)), for: .normal)
        capture.accessibilityLabel = AppLanguage.string("Take Photo")
        capture.addAction(UIAction { [weak controller, weak controls, weak coordinator = context.coordinator] _ in
            guard let controller, let coordinator, !coordinator.isCapturing else { return }
            coordinator.isCapturing = true
            controls?.isUserInteractionEnabled = false
            controller.takePicture()
        }, for: .touchUpInside)

        let flip = UIButton(type: .system)
        flip.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
        flip.accessibilityLabel = AppLanguage.string("Switch Camera")
        flip.isHidden = !UIImagePickerController.isCameraDeviceAvailable(.front)
        flip.addAction(UIAction { [weak controller] _ in
            guard let controller else { return }
            controller.cameraDevice = controller.cameraDevice == .rear ? .front : .rear
        }, for: .touchUpInside)

        for button in [cancel, capture, flip] {
            button.tintColor = .white
            button.backgroundColor = UIColor.black.withAlphaComponent(0.65)
            button.layer.cornerRadius = 12
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
            controls.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            controls.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
        controller.cameraOverlayView = overlay
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        var isCapturing = false
        private var hasFinished = false

        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func finish(_ photo: UIImage?) {
            guard !hasFinished else { return }
            hasFinished = true
            onFinish(photo)
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            finish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish(nil)
        }
    }
}
