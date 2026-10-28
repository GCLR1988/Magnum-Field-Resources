import SwiftUI
import Contacts
import ContactsUI

struct CompanyDirectoryView: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @State private var resources = SpreadsheetStore.shared
    @State private var search = ""
    @State private var contactToAdd: EmployeeContact?

    private struct ContactSection: Identifiable {
        let id: String
        let contacts: [EmployeeContact]
    }

    private var sections: [ContactSection] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let contacts = query.isEmpty ? resources.contacts : resources.contacts.filter { $0.matches(query) }
        return Dictionary(grouping: contacts, by: \.initial)
            .map { ContactSection(id: $0.key, contacts: $0.value) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    var body: some View {
        let groups = sections
        List {
            Section {
                HStack(spacing: 12) {
                    ResourceFolderIcon(name: "Company Directory")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Company Directory").font(.headline)
                        Text("\(resources.contacts.count) contacts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(groups) { section in
                Section {
                    ForEach(section.contacts) { contact in
                        EmployeeContactRow(contact: contact) {
                            contactToAdd = contact
                        }
                            .documentRowStyle()
                    }
                } header: {
                    Text(section.id).textCase(nil)
                }
            }
            if groups.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No contacts yet" : "No matching contacts",
                    systemImage: search.isEmpty ? "person.crop.rectangle" : "magnifyingglass",
                    description: Text(search.isEmpty
                        ? "Contacts will appear after the directory syncs."
                        : "Try a name, email address, or phone number.")
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(Color("WarmBackground"))
        .navigationTitle("Company Directory")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search names, emails, or phone numbers")
        .task { await resources.sync() }
        .refreshable { await catalogStore.syncAll() }
        .sheet(item: $contactToAdd) { contact in
            AddDirectoryContactView(contact: contact)
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            if let error = resources.errorMessage {
                StatusNotice(message: Text(error), systemImage: "exclamationmark.circle", isError: true)
            }
        }
    }
}

struct EmployeeContactRow: View {
    let contact: EmployeeContact
    let addContact: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(contact.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: addContact) {
                    Image(systemName: "person.badge.plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(AppStyle.accent.opacity(0.10), in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add \(contact.name) to Apple Contacts")
                .accessibilityHint("Review the contact details before saving")
            }
            if let url = contact.phoneURL {
                Link(destination: url) {
                    Label(contact.phone, systemImage: "phone.fill")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Call \(contact.name), \(contact.phone)")
            } else if !contact.phone.isEmpty {
                Label(contact.phone, systemImage: "phone")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let url = contact.emailURL {
                Link(destination: url) {
                    Label(contact.email, systemImage: "envelope.fill")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Email \(contact.name), \(contact.email)")
            } else if !contact.email.isEmpty {
                Text(contact.email).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .font(.subheadline)
        .tint(AppStyle.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .bookmarkAction(BookmarkKey.contact(contact.id))
    }
}

/// The system editor lets the person review and save without reading their address book.
struct AddDirectoryContactView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let contact: EmployeeContact

    func makeCoordinator() -> Coordinator {
        Coordinator { dismiss() }
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let newContact = CNMutableContact()
        // Preserve the spreadsheet's full name; the user can adjust name fields in the editor.
        newContact.givenName = contact.name
        if !contact.phone.isEmpty {
            newContact.phoneNumbers = [
                CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: contact.phone))
            ]
        }
        if !contact.email.isEmpty {
            newContact.emailAddresses = [
                CNLabeledValue(label: CNLabelWork, value: contact.email as NSString)
            ]
        }
        let controller = CNContactViewController(forNewContact: newContact)
        controller.contactStore = CNContactStore()
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        private let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            onDismiss()
        }
    }
}

struct CompanyDirectoryRow: View {
    var body: some View {
        HStack(spacing: 16) {
            ResourceFolderIcon(name: "Company Directory")
            Text("Company Directory")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .trainingCard()
    }
}

struct SpreadsheetLinkRow: View {
    let link: UsefulLink

    var body: some View {
        Link(destination: link.url) {
            HStack(spacing: 12) {
                ResourceFolderIcon(name: link.title + " link", compact: true)
                Text(link.title)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this link")
        .bookmarkAction(BookmarkKey.link(link.url))
        .documentRowStyle()
    }
}
