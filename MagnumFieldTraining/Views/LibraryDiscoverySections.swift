import SwiftUI

private enum LibraryEntry: Identifiable {
    case document(Program, WalkthroughResource)
    case website(WebGuide)
    case folder(Program, WalkthroughFolder?)
    case link(UsefulLink)
    case contact(EmployeeContact)
    case device(AppleDevice)
    case microsoft(MicrosoftTrainingApp)
    case directory
    case passwordReset
    case links
    case scan
    case photoMarkup

    var id: String {
        switch self {
        case .document(_, let resource): resource.persistenceKey
        case .website(let guide): guide.id
        case .folder(let program, let folder):
            folder.map { BookmarkKey.folder($0.id) } ?? BookmarkKey.program(program.id)
        case .link(let link): BookmarkKey.link(link.url)
        case .contact(let contact): BookmarkKey.contact(contact.id)
        case .device(let device): BookmarkKey.device(device.id)
        case .microsoft(let app): BookmarkKey.microsoft(app.id)
        case .directory: BookmarkKey.directory
        case .passwordReset: BookmarkKey.passwordReset
        case .links: BookmarkKey.links
        case .photoMarkup: BookmarkKey.photoMarkup
        case .scan: BookmarkKey.scan
        }
    }

    func matches(_ query: String) -> Bool {
        switch self {
        case .document(let program, let resource):
            "\(program.name) \(program.displayName(locale: AppLanguage.locale)) \(resource.title)".localizedStandardContains(query)
        case .website(let guide):
            guide.matches(query)
        case .folder(let program, let folder):
            (folder?.name ?? "\(program.name) \(program.displayName(locale: AppLanguage.locale))").localizedStandardContains(query)
        case .link(let link): link.title.localizedStandardContains(query)
        case .contact(let contact): contact.matches(query)
        case .device(let device): device.rawValue.localizedStandardContains(query)
        case .microsoft(let app): app.rawValue.localizedStandardContains(query)
        case .directory: AppLanguage.string("Company Directory").localizedStandardContains(query)
        case .passwordReset: AppLanguage.string("Password Reset Request").localizedStandardContains(query)
        case .links: AppLanguage.string("Useful Links").localizedStandardContains(query)
        case .photoMarkup: AppLanguage.string("Photo Markup").localizedStandardContains(query)
        case .scan: AppLanguage.string("Scan & Send").localizedStandardContains(query)
        }
    }
}

struct LibraryDiscoverySections: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @EnvironmentObject private var pinnedStore: PinnedStore
    @Environment(\.locale) private var locale
    @State private var resources = SpreadsheetStore.shared
    let query: String
    let openSavedForm: (SavedForm) -> Void
    @State private var filter: LibrarySearchFilter = .all
    @State private var downloadedOnly = false
    @State private var recents = RecentStore.shared

    private enum LibrarySearchFilter: String, CaseIterable, Identifiable {
        case all, forms, videos, guides
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .forms: "Forms"
            case .videos: "Videos"
            case .guides: "Guides"
            }
        }
    }

    private func accepts(_ entry: LibraryEntry) -> Bool {
        if downloadedOnly {
            guard case .document(_, let resource) = entry, resource.localSearchURL != nil else { return false }
        }
        switch filter {
        case .all: return true
        case .forms:
            if case .document(let program, let resource) = entry { return program.opensInFormEditor(resource) }
        case .videos:
            if case .document(_, let resource) = entry { return resource.kind == .video }
        case .guides:
            switch entry {
            case .document(let program, let resource):
                return resource.kind != .video && !program.opensInFormEditor(resource)
            case .website, .device, .microsoft: return true
            default: break
            }
        }
        return false
    }

    private var entries: [LibraryEntry] {
        var result = catalogStore.allDocuments.map { LibraryEntry.document($0.program, $0.resource) }
            + WebGuideCatalog.all.map { LibraryEntry.website($0) }
        func appendFolders(_ folders: [WalkthroughFolder], program: Program) {
            for folder in folders {
                result.append(.folder(program, folder))
                appendFolders(folder.subfolders, program: program)
            }
        }
        for program in catalogStore.programs {
            result.append(.folder(program, nil))
            appendFolders(catalogStore.rootFolder(for: program).subfolders, program: program)
        }
        result += resources.contacts.map { .contact($0) }
        result += resources.passwordResetLinks.map { .link($0) }
        result += resources.links.map { .link($0) }
        if !resources.hasLinks, let url = URL(string: "https://magnum.promotionaledgeshop.com") {
            result.append(.link(UsefulLink(title: AppLanguage.string("Magnum Swag Store"), url: url)))
        }
        result += AppleDevice.allCases.map { .device($0) }
        result += MicrosoftTrainingApp.allCases.map { .microsoft($0) }
        if resources.hasDirectory { result.append(.directory) }
        result += [.passwordReset, .links, .scan, .photoMarkup]
        // A URL or document can occur in more than one source.
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        let entries = entries
        let _ = locale.identifier // Refresh localized search matches when the interface language changes.
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if search.isEmpty {
            ContinueEditingSection(open: openSavedForm)
            let recent = recents.keys.compactMap { key in entries.first { $0.id == key } }
            if !recent.isEmpty {
                Section("Recently Used") {
                    ForEach(Array(recent.prefix(3))) { entry in
                        LibraryEntryRow(entry: entry).documentRowStyle()
                    }
                }
            }
            let bookmarked = entries.filter { pinnedStore.isPinned($0.id) }
            Section {
                ForEach(bookmarked) { entry in
                    LibraryEntryRow(entry: entry)
                        .documentRowStyle()
                }
                if bookmarked.isEmpty {
                    Label("Touch and hold an item, then choose Bookmark.", systemImage: "bookmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            } header: {
                Text("Bookmarked").textCase(nil)
            }
        } else {
            Section {
                Picker("Resource type", selection: $filter) {
                    ForEach(LibrarySearchFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                Toggle("Downloaded only", isOn: $downloadedOnly)
            }
            let filtered = entries.filter { accepts($0) }
            let matches = filtered.filter { $0.matches(search) }
            Section {
                ForEach(matches) { entry in
                    LibraryEntryRow(entry: entry)
                        .documentRowStyle()
                }
                if matches.isEmpty {
                    Text("No matching names. Check document content results below.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Matching Names (\(matches.count))").textCase(nil)
            }
            let documents = filtered.compactMap { entry -> LibrarySearchDocument? in
                guard case .document(let program, let resource) = entry, resource.kind == .pdf else { return nil }
                return LibrarySearchDocument(program: program, resource: resource)
            }
            PDFContentResultsSection(query: search, documents: documents, cacheVersion: catalogStore.cacheVersion)
        }
    }
}

private struct LibraryEntryRow: View {
    let entry: LibraryEntry
    var showsDetails: Bool = true
    @Environment(\.locale) private var locale
    @State private var selectedForm: WalkthroughResource?
    @State private var contactToAdd: EmployeeContact?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch entry {
            case .document(let program, let resource):
                if program.opensInFormEditor(resource) {
                    Button { selectedForm = resource } label: {
                        WalkthroughRow(resource: resource, subtitle: showsDetails ? program.displayName(locale: locale) : nil,
                                       showsTypeLabel: showsDetails)
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        WalkthroughDetailView(resource: resource)
                    } label: {
                        WalkthroughRow(resource: resource, subtitle: showsDetails ? program.displayName(locale: locale) : nil,
                                       showsTypeLabel: showsDetails)
                    }
                }
            case .website(let guide):
                WebGuideRow(guide: guide, showsDetails: showsDetails)
            case .folder(let program, let folder):
                NavigationLink {
                    ProgramDetailView(program: program, folder: folder)
                } label: {
                    Label(folder?.name ?? program.displayName(locale: locale), systemImage: "folder")
                }
                .bookmarkAction(entry.id)
            case .link(let link):
                SpreadsheetLinkRow(link: link)
            case .contact(let contact):
                EmployeeContactRow(contact: contact) { contactToAdd = contact }
            case .device(let device):
                NavigationLink {
                    DeviceGettingStartedView(device: device)
                } label: {
                    Label(device.rawValue, systemImage: device.symbol)
                }
                .bookmarkAction(entry.id)
            case .microsoft(let app):
                NavigationLink {
                    MicrosoftGettingStartedView(app: app)
                } label: {
                    Label(app.rawValue, systemImage: app.symbol)
                }
                .bookmarkAction(entry.id)
            case .directory:
                NavigationLink {
                    CompanyDirectoryView()
                } label: {
                    Label("Company Directory", systemImage: "person.crop.rectangle")
                }
                .bookmarkAction(entry.id)
            case .passwordReset:
                NavigationLink {
                    PasswordResetRequestView()
                } label: {
                    Label("Password Reset Request", systemImage: "key")
                }
                .bookmarkAction(entry.id)
            case .links:
                NavigationLink {
                    List { UsefulLinksSection() }
                        .navigationTitle("Useful Links")
                } label: {
                    Label("Useful Links", systemImage: "link")
                }
                .bookmarkAction(entry.id)
            case .photoMarkup:
                NavigationLink {
                    PhotoMarkupView()
                } label: {
                    Label("Photo Markup", systemImage: "photo.badge.plus")
                }
                .bookmarkAction(entry.id)
            case .scan:
                NavigationLink {
                    ScanAndSendView()
                } label: {
                    Label("Scan & Send", systemImage: "doc.viewfinder")
                }
                .bookmarkAction(entry.id)
            }
        }
        .sheet(item: $contactToAdd) { contact in
            AddDirectoryContactView(contact: contact).ignoresSafeArea()
        }
        .fullScreenCover(item: $selectedForm) { resource in
            FillableFormView(resource: resource)
        }
    }
}

private struct ContinueEditingSection: View {
    @State private var store = SavedFormStore.shared
    @State private var recents = RecentStore.shared
    let open: (SavedForm) -> Void

    private var forms: [SavedForm] {
        let recentlyOpened = recents.keys.compactMap { key in
            store.drafts.first { key == "saved-form:\($0.id.uuidString)" }
        }
        var seen = Set<UUID>()
        return Array((recentlyOpened + store.drafts).filter { seen.insert($0.id).inserted }.prefix(3))
    }

    var body: some View {
        if !forms.isEmpty {
            Section("Continue Editing") {
                ForEach(forms) { form in
                    Button { open(form) } label: { SavedFormRow(form: form) }
                        .buttonStyle(.plain)
                        .documentRowStyle()
                }
                NavigationLink("All Forms & Templates") { SavedFormsView() }
            }
        }
    }
}
