import SwiftUI
import PDFKit
import AVKit
import AVFoundation
import Combine

struct WalkthroughDetailView: View {
    @EnvironmentObject private var pinnedStore: PinnedStore
    @EnvironmentObject private var seenStore: SeenStore
    @EnvironmentObject private var catalogStore: CatalogStore
    let resource: WalkthroughResource

    @State private var pdfDocument: PDFDocument?
    @State private var player: AVPlayer?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cellularDownloadBlocked = false
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

    var body: some View {
        Group {
            if let pdfDocument {
                PDFKitRepresentedView(document: pdfDocument, pdfView: pdfView)
                    .ignoresSafeArea(edges: .bottom)
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .bottom)
            } else if isLoading {
                ProgressView("Downloading\u{2026}")
            } else {
                EmptyStateCard {
                    ContentUnavailableView {
                        Label(
                            resource.kind == .video ? "Video Not Found" : "PDF Not Found",
                            systemImage: cellularDownloadBlocked ? "wifi.slash" : "exclamationmark.triangle"
                        )
                    } description: {
                        Text(errorMessage ?? "Couldn't load this file.")
                    } actions: {
                        if cellularDownloadBlocked {
                            Button("Download Anyway") {
                                Task { await forceDownload() }
                            }
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
                                searchTask?.cancel()
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
                    Image(systemName: pinnedStore.isPinned(resource.persistenceKey) ? "pin.fill" : "pin")
                        .symbolEffect(.bounce, value: pinnedStore.isPinned(resource.persistenceKey))
                }
                .tint(Color("AccentColor"))
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
            seenStore.markSeen([resource.persistenceKey])
            await load()
        }
        .onDisappear {
            // Videos put the audio session into `.playback` (see
            // configureAudioSessionForPlayback) so training audio isn't silenced by
            // the ring/silent switch. Left active after leaving this screen, that
            // session keeps blocking anything the foreman had playing before they
            // opened the video (e.g. music/a podcast) from resuming on its own.
            // Pausing and deactivating here hands audio focus back once they're done.
            guard resource.kind == .video else { return }
            playerStatusSubscription?.cancel()
            player?.pause()
            Task.detached(priority: .utility) {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    private func load() async {
        isLoading = true
        cellularDownloadBlocked = false
        defer { isLoading = false }

        switch resource.location {
        case .bundled(let filename):
            let base = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            guard let url = Bundle.main.url(forResource: base, withExtension: ext.isEmpty ? nil : ext) else {
                errorMessage = "Couldn't find \"\(filename)\" in the app bundle. Make sure it's in the PDFs folder and checked under Target Membership."
                return
            }
            await apply(url)

        case .dropbox(let file):
            do {
                let wasCached = MediaCache.shared.isCached(file)
                let allowCellular = !SettingsStore.shared.wifiOnlyForVideos
                let url = try await MediaCache.shared.ensureCached(file, allowCellular: allowCellular)
                if !wasCached {
                    // Downloaded here rather than through CatalogStore's own sync/downloadAll
                    // (e.g. a foreman opened a file that wasn't pre-cached) -- bump
                    // cacheVersion so this file's row updates its cloud icon once we go back.
                    catalogStore.noteFileCached()
                }
                await apply(url)
            } catch MediaCacheError.wifiRequired {
                cellularDownloadBlocked = true
                errorMessage = "This video isn't downloaded yet, and you're not on Wi-Fi."
            } catch {
                errorMessage = "Couldn't get \(file.name) from Dropbox: \(error.localizedDescription)"
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
            let wasCached = MediaCache.shared.isCached(file)
            let url = try await MediaCache.shared.ensureCached(file, allowCellular: true)
            if !wasCached {
                catalogStore.noteFileCached()
            }
            await apply(url)
        } catch {
            errorMessage = "Couldn't get \(file.name) from Dropbox: \(error.localizedDescription)"
        }
    }

    private func apply(_ url: URL) async {
        switch resource.kind {
        case .pdf:
            pdfDocument = PDFDocument(url: url)
            if pdfDocument == nil {
                errorMessage = "Couldn't open \"\(resource.title)\" as a PDF."
            }
        case .video:
            await configureAudioSessionForPlayback()
            let newPlayer = AVPlayer(url: url)
            observePlaybackFailures(of: newPlayer)
            player = newPlayer
            newPlayer.play()
        }
    }

    /// Surfaces a video that fails to load (e.g. an interrupted or corrupted
    /// download) as the same kind of error message a broken PDF already shows,
    /// rather than silently leaving `player` set with nothing visibly happening.
    private func observePlaybackFailures(of newPlayer: AVPlayer) {
        playerStatusSubscription = newPlayer.publisher(for: \.currentItem?.status)
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { status in
                guard status == .failed else { return }
                let reason = newPlayer.currentItem?.error?.localizedDescription
                errorMessage = "Couldn't play \"\(resource.title)\"" + (reason.map { ": \($0)" } ?? ".")
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

    // MARK: - In-document search

    /// Debounces search-as-you-type: PDFDocument.findString is a synchronous,
    /// potentially slow scan of the whole document, and running it on the main
    /// thread on every single keystroke could make typing visibly stutter on a
    /// long walkthrough. Waiting for a short pause in typing keeps it off the
    /// critical path of every keystroke without changing the PDFKit threading.
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            performSearch()
        }
    }

    private func performSearch() {
        searchResults = []
        currentResultIndex = 0
        guard let pdfDocument, !searchText.isEmpty else {
            pdfView.clearSelection()
            return
        }
        searchResults = pdfDocument.findString(searchText, withOptions: [.caseInsensitive])
        if let first = searchResults.first {
            highlight(first)
        } else {
            pdfView.clearSelection()
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
