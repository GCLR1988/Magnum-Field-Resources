import SwiftUI
import PDFKit
import AVKit
import AVFoundation
import Combine
import QuickLook

private struct FormDocumentPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}

struct WalkthroughDetailView: View {
    @EnvironmentObject private var pinnedStore: PinnedStore
    @EnvironmentObject private var seenStore: SeenStore
    @EnvironmentObject private var catalogStore: CatalogStore
    let resource: WalkthroughResource

    @State private var previewURL: URL?
    @State private var pdfDocument: PDFDocument?
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var isVisible = false
    @State private var forceDownloadTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var cellularDownloadBlocked = false
    @State private var shouldRetryVideoDownload = false
    /// Watches the current video's `AVPlayerItem` for a hard failure (a corrupted or
    /// truncated download, most often) so that case gets the same "couldn't load"
    /// messaging a broken PDF already gets, instead of leaving a foreman looking at a
    /// blank, stuck player with no explanation. Replaced/cancelled each time a new
    /// video loads; cancelled for good in onDisappear.
    @State private var playerStatusSubscription: AnyCancellable?

    // Shared PDFView instance so this view (and the thumbnail strip) can
    // drive search and page navigation directly through PDFKit.
    @State private var pdfView = PDFView()
    @State private var isSearching = false
    @State private var showThumbnails = false
    @State private var searchText = ""
    @State private var searchResults: [PDFSelection] = []
    @State private var currentResultIndex = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var documentSearch: PDFSearchSession?

    var body: some View {
        Group {
            if let pdfDocument {
                PDFKitRepresentedView(document: pdfDocument, pdfView: pdfView)
                    .ignoresSafeArea(edges: .bottom)
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .bottom)
            } else if let previewURL {
                FormDocumentPreview(url: previewURL)
                    .ignoresSafeArea(edges: .bottom)
            } else if isLoading {
                ResourceLoadingView(title: "Opening file…")
            } else {
                EmptyStateCard {
                    VStack(spacing: 16) {
                        EmptyStateMessage(
                            title: cellularDownloadBlocked ? "Wi-Fi required" : "Unable to open file",
                            systemImage: cellularDownloadBlocked ? "wifi.slash" : "doc.badge.ellipsis",
                            message: Text(errorMessage ?? AppLanguage.string("Please try opening this file again."))
                        )
                        if cellularDownloadBlocked {
                            Button("Download Anyway") {
                                forceDownloadTask = Task { await forceDownload() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppStyle.accent)
                        } else {
                            Button("Try Again") {
                                forceDownloadTask = Task { await load() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppStyle.accent)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("WarmBackground"))
        .navigationTitle(resource.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if pdfDocument != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation { showThumbnails.toggle() }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            isSearching.toggle()
                            if !isSearching {
                                cancelSearch()
                                searchText = ""
                                searchResults = []
                                pdfView.clearSelection()
                            }
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    pinnedStore.toggle(resource.persistenceKey)
                } label: {
                    Image(systemName: pinnedStore.isPinned(resource.persistenceKey) ? "bookmark.fill" : "bookmark")
                        .symbolEffect(.bounce, value: pinnedStore.isPinned(resource.persistenceKey))
                }
                .tint(Color("AccentColor"))
                .accessibilityLabel(pinnedStore.isPinned(resource.persistenceKey) ? "Remove Bookmark" : "Bookmark")
            }
        }
        .safeAreaInset(edge: .top) {
            if isSearching {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search this document", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { _, _ in scheduleSearch() }
                    if !searchResults.isEmpty {
                        Text("\(currentResultIndex + 1)/\(searchResults.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    Button {
                        goToPreviousResult()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(searchResults.isEmpty)
                    Button {
                        goToNextResult()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(searchResults.isEmpty)
                }
                .padding(10)
                .background(.thinMaterial)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showThumbnails, pdfDocument != nil {
                PDFThumbnailBar(pdfView: pdfView)
                    .frame(height: 72)
                    .background(.thinMaterial)
            }
        }
        .task {
            isVisible = true
            // Preserve the current page and zoom when returning from another presentation.
            if pdfDocument != nil || previewURL != nil {
                if isSearching { scheduleSearch() }
                return
            }
            await load()
        }
        .onDisappear {
            isVisible = false
            forceDownloadTask?.cancel()
            cancelSearch()
            // Videos put the audio session into `.playback` (see
            // configureAudioSessionForPlayback) so training audio isn't silenced by
            // the ring/silent switch. Left active after leaving this screen, that
            // session keeps blocking anything the foreman had playing before they
            // opened the video (e.g. music/a podcast) from resuming on its own.
            // Pausing and deactivating here hands audio focus back once they're done.
            guard resource.kind == .video else { return }
            playerStatusSubscription?.cancel()
            player?.pause()
            Task { await deactivateAudioSession() }
        }
    }

    private func load() async {
        isLoading = true
        cellularDownloadBlocked = false
        errorMessage = nil
        defer { isLoading = false }

        switch resource.location {
        case .bundled(let filename):
            let base = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            guard let url = Bundle.main.url(forResource: base, withExtension: ext.isEmpty ? nil : ext) else {
                errorMessage = AppLanguage.string("This file is missing from the training library. Contact your administrator for help.")
                return
            }
            await apply(url)

        case .dropbox(let file):
            do {
                if shouldRetryVideoDownload {
                    await MediaCache.shared.invalidateCachedRevision(for: file)
                    shouldRetryVideoDownload = false
                }
                let neededDownload = await MediaCache.shared.needsDownload(file)
                let allowCellular = !SettingsStore.shared.wifiOnlyForVideos
                let url = try await MediaCache.shared.availableURL(for: file, allowCellular: allowCellular)
                if neededDownload {
                    // Downloaded here rather than through CatalogStore's own sync/downloadAll
                    // (e.g. a foreman opened a file that wasn't pre-cached) -- bump
                    // cacheVersion so this file's row updates its cloud icon once we go back.
                    await catalogStore.noteFileCached()
                }
                await apply(url)
            } catch MediaCacheError.wifiRequired {
                cellularDownloadBlocked = true
                errorMessage = AppLanguage.string("This video isn't downloaded yet, and you're not on Wi-Fi.")
            } catch {
                errorMessage = AppLanguage.string("Couldn't get \(file.name) from Dropbox: \(error.localizedDescription)")
            }
        }
    }

    /// Retries a Wi-Fi-gated video download, explicitly allowing cellular data.
    private func forceDownload() async {
        guard case .dropbox(let file) = resource.location else { return }
        isLoading = true
        cellularDownloadBlocked = false
        errorMessage = nil
        defer { isLoading = false }
        do {
            let neededDownload = await MediaCache.shared.needsDownload(file)
            let url = try await MediaCache.shared.ensureCached(file, allowCellular: true)
            if neededDownload {
                await catalogStore.noteFileCached()
            }
            await apply(url)
        } catch {
            errorMessage = AppLanguage.string("Couldn't get \(file.name) from Dropbox: \(error.localizedDescription)")
        }
    }

    private func apply(_ url: URL) async {
        // Shared cache downloads can finish after this screen's task is cancelled.
        guard isVisible, !Task.isCancelled else { return }
        switch resource.kind {
        case .document:
            previewURL = url
            recordOpenedFile()
        case .pdf:
            do {
                let document = try await FormDocumentLoader.load(from: url)
                guard isVisible, !Task.isCancelled else { return }
                pdfDocument = document
                recordOpenedFile()
            } catch is CancellationError {
                return
            } catch {
                guard isVisible, !Task.isCancelled else { return }
                if case .dropbox(let file) = resource.location {
                    await MediaCache.shared.invalidateCachedRevision(for: file)
                }
                errorMessage = AppLanguage.string("Couldn't open \"\(resource.title)\" as a PDF.")
            }
        case .video:
            await configureAudioSessionForPlayback()
            guard isVisible, !Task.isCancelled else {
                await deactivateAudioSession()
                return
            }
            let newPlayer = AVPlayer(url: url)
            observePlaybackFailures(of: newPlayer)
            player = newPlayer
            newPlayer.play()
        }
    }

    private func recordOpenedFile() {
        seenStore.markSeen([resource.persistenceKey])
        RecentStore.shared.record(resource.persistenceKey)
    }

    /// Surfaces a video that fails to load (e.g. an interrupted or corrupted
    /// download) as the same kind of error message a broken PDF already shows,
    /// rather than silently leaving `player` set with nothing visibly happening.
    private func observePlaybackFailures(of newPlayer: AVPlayer) {
        playerStatusSubscription = newPlayer.publisher(for: \.currentItem?.status)
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { status in
                guard isVisible, player === newPlayer else { return }
                if status == .readyToPlay {
                    recordOpenedFile()
                    return
                }
                guard status == .failed else { return }
                shouldRetryVideoDownload = true
                newPlayer.pause()
                let reason = newPlayer.currentItem?.error?.localizedDescription
                errorMessage = AppLanguage.string("Couldn't play \(resource.title): \(reason ?? "")")
                player = nil
            }
    }

    /// Without this, video playback uses the default "ambient" audio
    /// session, which iOS silences whenever the phone's ring/silent switch
    /// is flipped to silent (or the screen locks) -- the video visibly
    /// plays but with no sound. Since these are training walkthroughs a
    /// foreman needs to actually hear, `.playback` makes the audio play
    /// regardless of the silent switch, matching how apps like YouTube or
    /// Photos handle video audio.
    ///
    /// setCategory/setActive are synchronous calls that can block on
    /// hardware/driver work under the hood -- Xcode's Thread Performance
    /// Checker flags running them on the main thread as a hang risk. Making
    /// the actual calls from a detached background task keeps them off the
    /// view's main-actor context without needing a newer OS-only async API.
    private func configureAudioSessionForPlayback() async {
        await Task.detached(priority: .userInitiated) {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                // If this fails, playback still proceeds -- worst case, audio
                // falls back to the default session behavior described above.
            }
        }.value
    }

    private func deactivateAudioSession() async {
        await Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }.value
    }

    // MARK: - In-document search

    private func cancelSearch() {
        searchTask?.cancel()
        documentSearch?.cancel()
        documentSearch = nil
    }

    /// Debounce typing, then let PDFKit search asynchronously so long PDFs don't freeze the UI.
    private func scheduleSearch() {
        cancelSearch()
        searchResults = []
        currentResultIndex = 0
        pdfView.clearSelection()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearching, !query.isEmpty else { return }
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch { return }
            guard !Task.isCancelled, isVisible, isSearching, let pdfDocument else { return }
            let session = PDFSearchSession(document: pdfDocument) { results in
                searchResults = results
                currentResultIndex = 0
                if let first = results.first { highlight(first) }
            }
            documentSearch = session
            session.start(query)
        }
    }

    private func highlight(_ selection: PDFSelection) {
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)
    }

    private func goToNextResult() {
        guard !searchResults.isEmpty else { return }
        currentResultIndex = (currentResultIndex + 1) % searchResults.count
        highlight(searchResults[currentResultIndex])
    }

    private func goToPreviousResult() {
        guard !searchResults.isEmpty else { return }
        currentResultIndex = (currentResultIndex - 1 + searchResults.count) % searchResults.count
        highlight(searchResults[currentResultIndex])
    }
}

// PDFKit's Objective-C delegate protocol has no actor annotations. Searches are
// started on the main actor; @preconcurrency checks that isolation at callback time.
@MainActor
final class PDFSearchSession: NSObject, @preconcurrency PDFDocumentDelegate {
    private let document: PDFDocument
    private var results: [PDFSelection] = []
    private var completion: (([PDFSelection]) -> Void)?

    init(document: PDFDocument, completion: @escaping ([PDFSelection]) -> Void) {
        self.document = document
        self.completion = completion
    }

    func start(_ query: String) {
        document.delegate = self
        document.beginFindString(query, withOptions: [.caseInsensitive])
    }

    func didMatchString(_ instance: PDFSelection) {
        results.append(instance)
    }

    func documentDidEndDocumentFind(_ notification: Notification) {
        let callback = completion
        completion = nil
        document.delegate = nil
        callback?(results)
    }

    func cancel() {
        // Detach before cancelling, since cancellation can emit an end-of-search callback.
        completion = nil
        document.delegate = nil
        document.cancelFindString()
        results.removeAll()
    }
}
