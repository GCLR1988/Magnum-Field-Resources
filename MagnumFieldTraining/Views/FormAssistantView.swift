import SwiftUI
import PDFKit

/// Controls operate on the editor's PDF widgets, so saving and sharing use the same values.
struct FormAssistantView: View {
    let document: PDFDocument
    var reviewing = false
    var startsWithDates = false
    let onChange: () -> Void
    let onLocate: (FormField) -> Void
    let onShare: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var revision = 0
    @State private var selectedDates = Set<String>()
    @State private var showDates = false

    private var fields: [FormField] { FormFieldSupport.fields(in: document) }

    var body: some View {
        let fields = fields
        let _ = revision
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if reviewing {
                        Section {
                            Label("Review dates, names, and signatures before sharing.", systemImage: "checklist")
                            Text("Check each page too. Some required information may not be marked here.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        let missing = fields.filter(\.isMissing)
                        if !missing.isEmpty {
                            Section("Required fields to review") {
                                ForEach(missing) { field in
                                    Button {
                                        withAnimation { proxy.scrollTo(field.id, anchor: .top) }
                                    } label: {
                                        Label(field.name, systemImage: "exclamationmark.circle")
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                    if fields.isEmpty {
                        Section {
                            Text("This PDF has no fillable fields. Use Markup to add information, then review each page before sharing.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if startsWithDates { dateSection }
                        Section {
                            Text("Fill in the details below. Changes appear on your form as you type.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(0..<document.pageCount, id: \.self) { pageIndex in
                            let pageFields = fields.filter { $0.pageIndex == pageIndex }
                            if !pageFields.isEmpty {
                                Section("Page \(pageIndex + 1)") {
                                    ForEach(pageFields) { field in
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text(field.name).font(.headline)
                                            if field.isRequired {
                                                Text(field.isMissing ? "Required — please complete" : "Required")
                                                    .font(.caption)
                                                    .foregroundStyle(field.isMissing ? Color.red : Color.secondary)
                                            }
                                            fieldControl(field)
                                            Button("Show on Form", systemImage: "doc.text.magnifyingglass") {
                                                onLocate(field)
                                                dismiss()
                                            }
                                            .font(.subheadline)
                                        }
                                        .padding(.vertical, 6)
                                        .id(field.id)
                                    }
                                }
                            }
                        }
                        if !startsWithDates { dateSection }
                    }
                }
            }
            .navigationTitle(reviewing ? "Review Form" : "Fill Out Form")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if reviewing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Continue Sharing") {
                            onShare()
                            dismiss()
                        }
                    }
                }
            }
        }
        .tint(AppStyle.accent)
        .onAppear { showDates = startsWithDates }
    }

    @ViewBuilder
    private var dateSection: some View {
        let fields = fields
        if fields.contains(where: \.isDate) {
            Section {
                DisclosureGroup("Use Today’s Date", isExpanded: $showDates) {
                    Text("Choose the dates to change. Leave birth dates, incident dates, and other historical dates unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(fields.filter(\.isDate)) { field in
                        Toggle(isOn: Binding(
                            get: { selectedDates.contains(field.id) },
                            set: { if $0 { selectedDates.insert(field.id) } else { selectedDates.remove(field.id) } }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.name)
                                Text(FormFieldSupport.todayValue(replacing: field.annotation.widgetStringValue ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Update Selected Dates") {
                        for field in fields where selectedDates.contains(field.id) {
                            FormFieldSupport.setText(
                                FormFieldSupport.todayValue(replacing: field.annotation.widgetStringValue ?? ""),
                                for: field, in: document)
                        }
                        changed()
                        selectedDates.removeAll()
                        showDates = false
                    }
                    .disabled(selectedDates.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func fieldControl(_ field: FormField) -> some View {
        if field.annotation.isReadOnly || field.annotation.widgetFieldType == .signature {
            Text("Use Show on Form to review or sign here.")
                .font(.subheadline).foregroundStyle(.secondary)
        } else if field.annotation.widgetFieldType == .button {
            Toggle("Check this box", isOn: Binding(
                get: { field.annotation.buttonWidgetState != .offState },
                set: { FormFieldSupport.setChecked($0, for: field, in: document); changed() }
            ))
        } else if field.annotation.widgetFieldType == .choice, !field.options.isEmpty {
            Picker("Choose an option", selection: textBinding(field)) {
                Text("Not selected").tag("")
                ForEach(field.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        } else if field.annotation.widgetFieldType == .text {
            TextField("Enter your answer", text: textBinding(field), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(field.name)
        } else {
            Text("Review this field on the form.").foregroundStyle(.secondary)
        }
    }

    private func textBinding(_ field: FormField) -> Binding<String> {
        Binding(get: { field.annotation.widgetStringValue ?? "" }, set: {
            FormFieldSupport.setText($0, for: field, in: document)
            changed()
        })
    }

    private func changed() {
        revision += 1
        onChange()
    }
}
