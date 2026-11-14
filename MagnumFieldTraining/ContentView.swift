import SwiftUI
import UIKit
import Foundation
import UniformTypeIdentifiers

enum ResourceDestination: Hashable {
    case home
    case directory
    case program(String)
    case links
    case scan
    case savedForms
}

struct ContentView: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @State private var resources = SpreadsheetStore.shared
    @State private var selection: ResourceDestination? = .home
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var showSettings = false
    @State private var presentedForms: Program?
    @ObservedObject private var downloadSettings = SettingsStore.shared
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @Environment(\.scenePhase) private var scenePhase

    private var shouldAutoDownload: Bool {
        downloadSettings.autoDownloadOnWiFi && networkMonitor.isWiFiConnected && scenePhase == .active
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            ResourceSidebar(selection: $selection, programs: catalogStore.programs,
                            hasDirectory: resources.hasDirectory)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            NavigationStack {
                ResourceDestinationView(destination: selection ?? .home) { destination in
                    if case .program(let id) = destination,
                       let program = catalogStore.programs.first(where: { $0.id == id }),
                       program.isDownloadableForms {
                        presentedForms = program
                    } else {
                        selection = destination
                        compactColumn = .detail
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AppLanguageToggle()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gearshape") { showSettings = true }
                    }
                }
            }
            .id(selection)
        }
        .navigationSplitViewStyle(.balanced)
        .fullScreenCover(item: $presentedForms) { program in
            NavigationStack {
                ProgramDetailView(program: program)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { presentedForms = nil }
                        }
                        ToolbarItem(placement: .topBarTrailing) { AppLanguageToggle() }
                    }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(settingsStore: SettingsStore.shared)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await catalogStore.syncAll()
        }
        .task(id: shouldAutoDownload) {
            guard shouldAutoDownload else { return }
            await catalogStore.syncAll()
            guard !Task.isCancelled else { return }
            await catalogStore.downloadAutomaticallyOnWiFi()
        }
        .onChange(of: catalogStore.programs.map(\.id)) { _, ids in
            if case .program(let id) = selection, !ids.contains(id) { selection = .home }
        }
    }
}

private struct ResourceSidebar: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var catalogStore: CatalogStore
    @Binding var selection: ResourceDestination?
    let programs: [Program]
    let hasDirectory: Bool

    private var visiblePrograms: [Program] {
        programs.filter { !$0.isCompanyNewsletter }.sorted {
            let left = $0.resourceOrder
            let right = $1.resourceOrder
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left < right
        }
    }

    var body: some View {
        List(selection: $selection) {
            NavigationLink(value: ResourceDestination.home) {
                Label("Home", systemImage: "square.grid.2x2")
            }
            Section("Resources") {
                programRows(visiblePrograms.filter { $0.resourceOrder < 4 })
                NavigationLink(value: ResourceDestination.savedForms) {
                    HStack(spacing: 10) {
                        ResourceFolderIcon(name: "My Forms & Templates", compact: true)
                        Text("My Forms & Templates")
                    }
                }
                if hasDirectory {
                    NavigationLink(value: ResourceDestination.directory) {
                        HStack(spacing: 10) {
                            ResourceFolderIcon(name: "Company Directory", compact: true)
                            Text("Company Directory")
                        }
                    }
                    .bookmarkAction(BookmarkKey.directory)
                }
                NavigationLink(value: ResourceDestination.links) {
                    HStack(spacing: 10) {
                        ResourceFolderIcon(name: "Useful Links", compact: true)
                        Text("Useful Links")
                    }
                }
                .bookmarkAction(BookmarkKey.links)
                NavigationLink(value: ResourceDestination.scan) {
                    Label("Scan & Send", systemImage: "doc.viewfinder")
                }
                .bookmarkAction(BookmarkKey.scan)
            }
            if visiblePrograms.contains(where: { $0.resourceOrder == 4 }) {
                Section("More Resources") {
                    programRows(visiblePrograms.filter { $0.resourceOrder == 4 })
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(AppStyle.background)
        .navigationTitle("Magnum")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let lastSyncedAt = catalogStore.lastSyncedAt {
                Text("Last synced \(Text(lastSyncedAt, style: .relative)) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(AppStyle.background)
            }
        }
    }

    @ViewBuilder
    private func programRows(_ items: [Program]) -> some View {
        ForEach(items) { program in
            NavigationLink(value: ResourceDestination.program(program.id)) {
                HStack(spacing: 10) {
                    FolderArtwork(name: program.name, logo: catalogStore.logo(for: program), compact: true)
                    Text(program.displayName(locale: locale))
                }
            }
            .bookmarkAction(BookmarkKey.program(program.id))
        }
    }
}

private struct ResourceDestinationView: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    let destination: ResourceDestination
    let select: (ResourceDestination) -> Void

    var body: some View {
        Group {
            switch destination {
            case .home:
                ResourceHomeView(select: select)
            case .directory:
                CompanyDirectoryView()
            case .program(let id):
                if let program = catalogStore.programs.first(where: { $0.id == id }) {
                    ProgramDetailView(program: program)
                } else {
                    ContentUnavailableView("Folder unavailable", systemImage: "folder")
                }
            case .savedForms:
                SavedFormsView()
            case .scan:
                ScanAndSendView()
            case .links:
                List { UsefulLinksSection() }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color("WarmBackground"))
                    .navigationTitle("Useful Links")
                    .refreshable { await catalogStore.syncAll() }
            }
        }
    }
}

private struct ResourceHomeView: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @Environment(\.locale) private var locale
    @State private var resources = SpreadsheetStore.shared
    @State private var search = ""
    @State private var selectedSavedForm: SavedForm?
    let select: (ResourceDestination) -> Void

    private var primaryPrograms: [Program] {
        catalogStore.programs.filter { !$0.isCompanyNewsletter && $0.resourceOrder < 4 }
            .sorted { $0.resourceOrder < $1.resourceOrder }
    }

    private var otherPrograms: [Program] {
        catalogStore.programs.filter {
            !$0.isCompanyNewsletter && $0.resourceOrder == 4
        }
    }

    var body: some View {
        List {
            if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    TrainingIntroduction()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            if let announcement = catalogStore.announcement {
                AnnouncementSection(announcement: announcement)
            }
            if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Saved forms are available even before the library has synced.
                Section("Resources") {
                    ResourceTileGrid {
                        ForEach(primaryPrograms) { program in
                            Button { select(.program(program.id)) } label: {
                                ProgramResourceTile(program: program)
                            }
                            .buttonStyle(ResourcePressStyle())
                            .bookmarkAction(BookmarkKey.program(program.id))
                        }
                        Button { select(.savedForms) } label: {
                            LandingFolderTile(name: "My Forms & Templates", title: AppLanguage.string("My Forms & Templates", locale: locale))
                        }
                        .buttonStyle(ResourcePressStyle())
                        if resources.hasDirectory {
                            Button { select(.directory) } label: {
                                LandingFolderTile(name: "Company Directory", title: AppLanguage.string("Company Directory", locale: locale))
                            }
                            .buttonStyle(ResourcePressStyle())
                            .bookmarkAction(BookmarkKey.directory)
                        }
                        Button { select(.links) } label: {
                            LandingFolderTile(name: "Useful Links", title: AppLanguage.string("Useful Links", locale: locale))
                        }
                        .buttonStyle(ResourcePressStyle())
                        .bookmarkAction(BookmarkKey.links)
                        Button { select(.scan) } label: {
                            LandingFolderTile(name: "Scan & Send", title: AppLanguage.string("Scan & Send", locale: locale))
                        }
                        .buttonStyle(ResourcePressStyle())
                        .bookmarkAction(BookmarkKey.scan)
                    }
                    .resourceGridRow()
                }
                if !otherPrograms.isEmpty {
                    Section("More Resources") {
                        ResourceTileGrid {
                            ForEach(otherPrograms) { program in
                                Button { select(.program(program.id)) } label: {
                                    ProgramResourceTile(program: program)
                                }
                                .buttonStyle(ResourcePressStyle())
                                .bookmarkAction(BookmarkKey.program(program.id))
                            }
                        }
                        .resourceGridRow()
                    }
                }
            }
            LibraryDiscoverySections(query: search, openSavedForm: { selectedSavedForm = $0 })
            if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OfflineReadinessView()
            }
            if catalogStore.programs.isEmpty && !resources.hasDirectory && search.isEmpty {
                Section {
                    Text("Your resources will appear here after the first update.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(AppStyle.sectionSpacing))
        .scrollContentBackground(.hidden)
        .background(Color("WarmBackground"))
        .navigationTitle("Field Resources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Field Resources")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.8)
            }
        }
        .fullScreenCover(item: $selectedSavedForm) { form in
            FillableFormView(savedForm: form)
        }
        .searchable(text: $search, prompt: "Search guides and walkthroughs")
        .refreshable { await catalogStore.syncAll() }
        .overlay(alignment: .bottomTrailing) { DownloadProgressIndicator() }
        .safeAreaInset(edge: .bottom, spacing: 0) { LibraryStatusFooter() }
    }
}

private struct ProgramResourceTile: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var catalogStore: CatalogStore
    let program: Program

    private var subtitle: String? {
        switch catalogStore.status(for: program) {
        case .failed: return AppLanguage.string("Update unavailable", locale: locale)
        case .syncing: return AppLanguage.string("Updating…", locale: locale)
        default: return nil
        }
    }

    var body: some View {
        let _ = catalogStore.cacheVersion
        LandingFolderTile(name: program.name,
                          title: program.displayName(locale: locale),
                          subtitle: subtitle,
                          logo: catalogStore.logo(for: program))
    }
}

struct UsefulLinksSection: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @State private var resources = SpreadsheetStore.shared

    private var newsletter: WalkthroughResource? {
        guard let program = catalogStore.programs.first(where: \.isCompanyNewsletter) else { return nil }
        return catalogStore.documents(for: program).first { $0.kind == .pdf }
    }

    var body: some View {
        Section {
            if let newsletter {
                NavigationLink { WalkthroughDetailView(resource: newsletter) } label: {
                    Label("Company Newsletter", systemImage: "newspaper")
                        .foregroundStyle(.primary)
                }
                .documentRowStyle()
                .bookmarkAction(newsletter.persistenceKey)
            }
            if resources.hasLinks {
                ForEach(resources.links) { link in
                    SpreadsheetLinkRow(link: link)
                }
                if resources.links.isEmpty {
                    Text("No useful links available yet.").foregroundStyle(.secondary)
                }
            } else if let url = URL(string: "https://magnum.promotionaledgeshop.com") {
                Link(destination: url) {
                    HStack {
                        Label("Magnum Swag Store", systemImage: "bag")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption)
                    }
                }
                .documentRowStyle()
                .bookmarkAction(BookmarkKey.link(url))
            }
        } header: { Text("Useful Links").font(.headline).textCase(nil) }
    }
}

private struct LibraryStatusFooter: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor


    private var failedSyncPrograms: [Program] {
        catalogStore.programs.filter {
            if case .failed = catalogStore.status(for: $0) { return true }
            return false
        }
    }

    private var failedProgramNames: String {
        let names: [String] = failedSyncPrograms.map(\.name)
        return names.formatted(.list(type: .and).locale(AppLanguage.locale))
    }

    var body: some View {
        VStack(spacing: 0) {
            DownloadRecoveryNotice()
            if catalogStore.hasPendingDownloads && catalogStore.failedDownloads.isEmpty && catalogStore.activeDownloads.isEmpty {
                HStack(spacing: 8) {
                    if catalogStore.isDownloadingPending {
                        ProgressView().controlSize(.small)
                        Text("Downloading…")
                    } else {
                        Image(systemName: "arrow.down.circle")
                        Text("Files ready to download")
                        Spacer()
                        Button("Download") {
                            Task { await catalogStore.downloadAllPending() }
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            if !networkMonitor.isConnected {
                StatusNotice(
                    message: Text("You're offline. Downloaded content is available."),
                    systemImage: "wifi.slash"
                )
            } else if let error = SpreadsheetStore.shared.errorMessage {
                StatusNotice(message: Text(error), systemImage: "exclamationmark.circle", isError: true)
            } else if let announcementError = catalogStore.announcementError {
                StatusNotice(
                    message: Text("Couldn't update the announcement: \(announcementError)"),
                    systemImage: "exclamationmark.circle",
                    isError: true
                )
            } else if let discoveryError = catalogStore.discoveryError {
                StatusNotice(
                    message: Text("Couldn't update the library: \(discoveryError)"),
                    systemImage: "exclamationmark.circle",
                    isError: true
                )
            } else if !failedSyncPrograms.isEmpty {
                StatusNotice(
                    message: Text("Couldn't update \(failedProgramNames). Pull down to retry."),
                    systemImage: "exclamationmark.circle",
                    isError: true
                )
            }

        }
        .background(.regularMaterial)
    }
}

struct DownloadableFormCard: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var showDownloadError = false
    @State private var showSaveSuccess = false
    @State private var saveSucceeded = false
    @State private var exportFile: FormExportFile?
    @State private var exportCleanup: FormExportFile?
    @State private var isSharing = false
    @State private var downloadTask: Task<Void, Never>?
    let file: DropboxFileMetadata
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 42, height: 48)
                        .background(Color("AccentColor").opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text((file.name as NSString).deletingPathExtension)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        let _ = catalogStore.cacheVersion
                        Text(MediaCache.shared.isCached(file) ? "Available offline" : "Download on open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(ResourcePressStyle())
            .accessibilityHint("Opens this form")

            Menu {
                Button("Save to Files", systemImage: "folder") { prepareForm(forSharing: false) }
                Button("Share", systemImage: "square.and.arrow.up") { prepareForm(forSharing: true) }
            } label: {
                Group {
                    if isDownloading { ProgressView() }
                    else { Image(systemName: "ellipsis").font(.body.weight(.semibold)) }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .tint(AppStyle.accent)
            .disabled(isDownloading || exportFile != nil || catalogStore.isClearingCache)
            .accessibilityLabel("Form Actions")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $exportFile, onDismiss: {
            exportCleanup?.removeTemporaryCopy()
            exportCleanup = nil
            if downloadError != nil {
                showDownloadError = true
            } else if saveSucceeded {
                saveSucceeded = false
                showSaveSuccess = true
            }
        }) { prepared in
            if isSharing {
                FormShareSheet(url: prepared.url) { error in
                    prepared.removeTemporaryCopy()
                    exportFile = nil
                    if let error {
                        downloadError = error.localizedDescription
                    }
                }
            } else {
                FormSavePicker(url: prepared.url) { result in
                    // Keep the source until Files and any provider fallback finish.
                    Task.detached(priority: .utility) {
                        prepared.removeTemporaryCopy()
                    }
                    exportFile = nil
                    switch result {
                    case .failure(let error):
                        downloadError = error.localizedDescription
                    case .success(let url):
                        saveSucceeded = url != nil
                    }
                }
            }
        }
        .onDisappear {
            downloadTask?.cancel()
        }
        .sensoryFeedback(.success, trigger: showSaveSuccess) { _, saved in saved }
        .alert("Form saved", isPresented: $showSaveSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your form is saved in the folder you selected.")
        }
        .alert(isSharing ? "Unable to share form" : "Unable to save form", isPresented: $showDownloadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadError ?? AppLanguage.string("Please try again."))
        }
    }

    private func prepareForm(forSharing: Bool) {
        downloadError = nil
        showDownloadError = false
        saveSucceeded = false
        isSharing = forSharing
        isDownloading = true
        downloadTask = Task {
            defer { isDownloading = false }
            do {
                let url = try await MediaCache.shared.availableURL(for: file)
                // Export a separate copy with the original filename, without loading
                // the entire form into memory or exposing the cache's encoded name.
                let filename = file.name
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try FormExportFile.prepare(source: url, filename: filename)
                }.value
                var presented = false
                defer {
                    if !presented { prepared.removeTemporaryCopy() }
                }
                try Task.checkCancellation()
                await catalogStore.noteFileCached()
                try Task.checkCancellation()
                exportCleanup = prepared
                exportFile = prepared
                presented = true
            } catch is CancellationError {
                // Cache clearing can cancel an active download.
            } catch {
                downloadError = error.localizedDescription
                showDownloadError = true
            }
        }
    }
}

private struct FormShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: (Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Share the actual file, preserving its name and extension for recipients.
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in
            onFinish(error)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct FormSavePicker: UIViewControllerRepresentable {
    let url: URL
    let onFinish: (Result<URL?, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(source: url, onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Choose a directory, then perform one coordinated copy ourselves.
        // This avoids ambiguous provider results from the export/Keep Both flow.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.title = AppLanguage.string("Choose a Folder to Save This Form")
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let source: URL
        let onFinish: (Result<URL?, Error>) -> Void

        init(source: URL, onFinish: @escaping (Result<URL?, Error>) -> Void) {
            self.source = source
            self.onFinish = onFinish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let destination = urls.first else {
                onFinish(.failure(CocoaError(.fileWriteUnknown)))
                return
            }
            let source = source
            Task {
                do {
                    let savedURL = try await Task.detached(priority: .userInitiated) {
                        try FormExportFile.finishExport(source: source, destination: destination)
                    }.value
                    onFinish(.success(savedURL))
                } catch {
                    onFinish(.failure(error))
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish(.success(nil))
        }
    }
}

private struct PendingDownloadsButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isDownloading: Bool
    let download: () -> Void

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        layout {
            Label(
                isDownloading ? "Downloading content…" : "New content available",
                systemImage: "arrow.down.circle"
            )
            .font(.subheadline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isDownloading {
                ProgressView()
                    .tint(Color("AccentColor"))
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Button("Download", action: download)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Color("AccentColor"))
                    .controlSize(.regular)
                    .frame(minHeight: 44)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(16)
        .background(Color("WarmCard"), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("Status and empty states") {
    ScrollView {
        VStack(spacing: 24) {
            PendingDownloadsButton(isDownloading: false, download: {})
            PendingDownloadsButton(isDownloading: true, download: {})
            StatusNotice(
                message: Text("You're offline. Downloaded content is available."),
                systemImage: "wifi.slash"
            )
            EmptyStateCard {
                EmptyStateMessage(
                    title: "No walkthroughs yet",
                    systemImage: "doc.text.magnifyingglass",
                    message: Text("Walkthroughs will appear here when they're added to this program.")
                )
            }
        }
        .padding(20)
        .frame(maxWidth: 390)
        .frame(maxWidth: .infinity)
    }
    .background(Color("WarmBackground"))
}

#if DEBUG
#Preview("Home — compact") {
    NavigationStack {
        ResourceHomeView(select: { _ in })
    }
    .environmentObject(PinnedStore())
    .environmentObject(CatalogStore.previewCatalog())
    .environmentObject(SeenStore())
    .environmentObject(NetworkMonitor.shared)
}

#Preview("Home — sidebar") {
    ResourceLayoutPreview()
}

private struct ResourceLayoutPreview: View {
    @State private var selection: ResourceDestination? = .home
    @StateObject private var catalog = CatalogStore.previewCatalog()

    var body: some View {
        NavigationSplitView {
            ResourceSidebar(selection: $selection, programs: catalog.programs, hasDirectory: true)
        } detail: {
            NavigationStack {
                ResourceDestinationView(destination: selection ?? .home) { selection = $0 }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environmentObject(PinnedStore())
        .environmentObject(catalog)
        .environmentObject(SeenStore())
        .environmentObject(NetworkMonitor.shared)
    }
}
#endif

private struct OfflineReadinessView: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.locale) private var locale
    @State private var resources = SpreadsheetStore.shared
    @State private var available = 0
    @State private var pending: [PendingFile] = []
    @State private var checked = false
    @State private var downloading = false
    @State private var showDetails = false

    private struct PendingFile: Identifiable {
        let file: DropboxFileMetadata
        let hasOlderCopy: Bool
        var id: String { file.id }
    }

    private struct Snapshot: Equatable {
        let files: [DropboxFileMetadata]
        let cacheVersion: Int
        let isDownloading: Bool
    }

    private var files: [DropboxFileMetadata] {
        var seen = Set<String>()
        let documents = catalogStore.allDocuments.compactMap { item -> DropboxFileMetadata? in
            if case .dropbox(let file) = item.resource.location { return file }
            return nil
        }
        return (documents + resources.sourceFiles).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        Section("Offline Access") {
            VStack(alignment: .leading, spacing: 12) {
                if checked {
                    Label("\(available) of \(files.count) files available offline",
                          systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                    if !pending.isEmpty {
                        Button { showDetails = true } label: {
                            Label("\(pending.count) files need a download or update", systemImage: "arrow.down.circle")
                                .font(.subheadline)
                        }
                    } else if !files.isEmpty {
                        Text("Downloaded files are up to date.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView("Checking downloads…")
                }
                if let lastSync = catalogStore.lastSyncedAt {
                    Text("Library last checked: \(lastSync.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Update the library online before preparing offline access.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    downloading = true
                    Task {
                        await catalogStore.syncAll()
                        await catalogStore.downloadAllPending()
                        downloading = false
                    }
                } label: {
                    Label(downloading || catalogStore.isDownloadingPending ? "Downloading…" : "Download for Offline Use",
                          systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .disabled(downloading || catalogStore.isDownloadingPending || catalogStore.isClearingCache || !network.isConnected)
                if !network.isConnected {
                    Text("You’re offline. Downloaded files and saved forms are still available.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
        .task(id: Snapshot(files: files, cacheVersion: catalogStore.cacheVersion,
                           isDownloading: catalogStore.isDownloadingPending)) {
            let snapshot = files
            var ready = 0
            var remaining: [PendingFile] = []
            for file in snapshot {
                let cached = MediaCache.shared.isCached(file)
                if cached { ready += 1 }
                if await MediaCache.shared.needsDownload(file) {
                    remaining.append(PendingFile(file: file, hasOlderCopy: cached))
                }
                guard !Task.isCancelled else { return }
            }
            available = ready
            pending = remaining
            checked = true
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                List(pending) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text((item.file.name as NSString).deletingPathExtension).font(.body.weight(.semibold))
                        Text(item.hasOlderCopy ? "Older copy available offline; update pending" : "Not downloaded")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Pending Downloads")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDetails = false } } }
            }
        }
    }
}
