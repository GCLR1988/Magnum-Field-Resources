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
    case links
    case scan

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
        case .links: BookmarkKey.links
        case .scan: BookmarkKey.scan
        }
    }

    func matches(_ query: String) -> Bool {
        switch self {
        case .document(let program, let resource):
            "\(program.name) \(resource.title)".localizedStandardContains(query)
        case .website(let guide):
            guide.matches(query)
        case .folder(let program, let folder):
            (folder?.name ?? program.name).localizedStandardContains(query)
        case .link(let link): link.title.localizedStandardContains(query)
        case .contact(let contact): contact.matches(query)
        case .device(let device): device.rawValue.localizedStandardContains(query)
        case .microsoft(let app): app.rawValue.localizedStandardContains(query)
        case .directory: AppLanguage.string("Company Directory").localizedStandardContains(query)
        case .links: AppLanguage.string("Useful Links").localizedStandardContains(query)
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
        result += resources.links.map { .link($0) }
        if !resources.hasLinks, let url = URL(string: "https://magnum.promotionaledgeshop.com") {
            result.append(.link(UsefulLink(title: AppLanguage.string("Magnum Swag Store"), url: url)))
        }
        result += AppleDevice.allCases.map { .device($0) }
        result += MicrosoftTrainingApp.allCases.map { .microsoft($0) }
        if resources.hasDirectory { result.append(.directory) }
        result += [.links, .scan]
        // A URL or document can occur in more than one source.
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        let entries = entries
        let _ = locale.identifier // Refresh localized search matches when the interface language changes.
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if search.isEmpty {
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
            let matches = entries.filter { $0.matches(search) }
            if matches.isEmpty {
                ContentUnavailableView.search(text: search)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(matches) { entry in
                        LibraryEntryRow(entry: entry)
                            .documentRowStyle()
                    }
                } header: {
                    Text("Results (\(matches.count))").textCase(nil)
                }
            }
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
            case .links:
                NavigationLink {
                    List { UsefulLinksSection() }
                        .navigationTitle("Useful Links")
                } label: {
                    Label("Useful Links", systemImage: "link")
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
