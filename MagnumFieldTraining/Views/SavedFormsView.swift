import SwiftUI

struct SavedFormsView: View {
    @State private var store = SavedFormStore.shared
    @State private var selection: FormSelection?
    @State private var renameTarget: SavedForm?
    @State private var deleteTarget: SavedForm?
    @State private var name = ""
    @State private var errorMessage: String?

    private struct FormSelection: Identifiable {
        let form: SavedForm
        var editTemplate = false
        var id: UUID { form.id }
    }

    var body: some View {
        List {
            Section {
                Text("Your forms and templates keep their entered information and markup on this device, even after closing the app. Open a saved form to continue editing, or tap a template to start a separate form with its saved information.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let loadError = store.loadError {
                Section {
                    Text(loadError).foregroundStyle(.red)
                    Button("Try Again") { store.reload() }
                }
            }
            Section("Saved Forms") {
                if store.drafts.isEmpty {
                    Text("Only forms you add appear here. Fill out a library form, then tap Add to My Forms & Templates and choose Save Form.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.drafts) { form in
                    row(form)
                }
            }
            Section("Personal Templates") {
                if store.templates.isEmpty {
                    Text("Fill in your usual information, tap Add to My Forms & Templates at the bottom of the editor, then choose Save as Reusable Template.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.templates) { form in
                    row(form)
                }
            }
            if !store.earlierForms.isEmpty {
                Section {
                    DisclosureGroup("Earlier Autosaved Forms") {
                        Text("Earlier versions saved these forms automatically. Open one and use Add to My Forms & Templates to keep it in Saved Forms.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(store.earlierForms) { form in
                            row(form)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(AppStyle.sectionSpacing))
        .scrollContentBackground(.hidden)
        .background(AppStyle.background)
        .navigationTitle("My Forms & Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("My Forms & Templates")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.8)
            }
        }
        .fullScreenCover(item: $selection) { selected in
            FillableFormView(savedForm: selected.form, editingTemplate: selected.editTemplate)
        }
        .alert("Rename", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $name)
            Button("Save") {
                if let form = renameTarget {
                    perform { try store.rename(form, to: name) }
                }
                renameTarget = nil
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog("Delete saved form?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let form = deleteTarget { perform { try store.delete(form) } }
                deleteTarget = nil
            }
        } message: {
            Text("This removes this saved copy from this device.")
        }
        .alert("Couldn't update saved form", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(_ form: SavedForm) -> some View {
        Button {
            selection = FormSelection(form: form)
        } label: {
            SavedFormRow(form: form)
        }
        .buttonStyle(.plain)
        .documentRowStyle()
        .contextMenu {
            if form.kind == .template {
                Button("Edit Template", systemImage: "pencil") {
                    selection = FormSelection(form: form, editTemplate: true)
                }
            }
            Button("Rename", systemImage: "pencil.line") {
                name = form.name
                renameTarget = form
            }
            Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = form }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = form }
        }
        .accessibilityHint(form.kind == .template ? "Creates a new draft from this template" : "Opens this saved draft")
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}
