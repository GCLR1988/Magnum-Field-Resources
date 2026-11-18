import AppKit
import PDFKit
import Testing
@testable import FormLibrary

@Test @MainActor
func generatedSafetyFieldNamesUseReadableFallbacks() {
    for identifier in ["newTxtJobName00", "newTxtJobName10", "newTxtSpecialTopics00", "f1_2"] {
        let annotation = PDFAnnotation(bounds: .zero, forType: .widget, withProperties: nil)
        annotation.widgetFieldType = .text
        annotation.fieldName = identifier
        let field = FormField(id: "0:2", pageIndex: 0, annotation: annotation)
        #expect(field.name == AppLanguage.string("Field \(3)"))
        annotation.setValue(identifier, forAnnotationKey: .widgetTextLabelUI)
        #expect(field.name == AppLanguage.string("Field \(3)"))
        annotation.setValue("Job name / Nombre del trabajo", forAnnotationKey: .widgetTextLabelUI)
        #expect(field.name == "Job name / Nombre del trabajo")
        #expect(annotation.fieldName == identifier)
    }
    let annotation = PDFAnnotation(bounds: .zero, forType: .widget, withProperties: nil)
    annotation.fieldName = "OSHA_300"
    #expect(FormField(id: "0:0", pageIndex: 0, annotation: annotation).name == "OSHA 300")
    annotation.widgetFieldType = .text
    annotation.fieldName = "newTxtMeetingDate00"
    #expect(FormField(id: "0:0", pageIndex: 0, annotation: annotation).isDate)
}

@MainActor
private func makeForm() -> PDFDocument {
    let document = PDFDocument()
    let page = PDFPage()
    page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
    document.insert(page, at: 0)
    let field = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 200, height: 30), forType: .widget, withProperties: nil)
    field.widgetFieldType = .text
    field.fieldName = "date"
    field.widgetStringValue = "November 13"
    page.addAnnotation(field)
    let checkbox = PDFAnnotation(bounds: CGRect(x: 20, y: 60, width: 20, height: 20), forType: .widget, withProperties: nil)
    checkbox.widgetFieldType = .button
    checkbox.widgetControlType = .checkBoxControl
    checkbox.fieldName = "checked"
    checkbox.buttonWidgetState = .onState
    page.addAnnotation(checkbox)
    let ink = PDFAnnotation(bounds: CGRect(x: 20, y: 100, width: 100, height: 50), forType: .ink, withProperties: nil)
    ink.userName = "MagnumFieldTraining.UserInk"
    let path = NSBezierPath()
    path.move(to: .zero)
    path.line(to: CGPoint(x: 70, y: 30))
    ink.add(path)
    page.addAnnotation(ink)
    return document
}

@Test @MainActor
func savedFormsPreserveFieldsAndInkWithoutChangingTemplates() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SavedFormStore(directory: directory)
    let template = try store.save(document: makeForm(), id: UUID(), name: "Usual Form", kind: .template)
    let copy = try store.document(for: template)
    copy.page(at: 0)?.annotations.first(where: { $0.fieldName == "date" })?.widgetStringValue = "November 14"
    let draft = try store.save(document: copy, id: UUID(), name: "Today", kind: .draft)
    let reopened = SavedFormStore(directory: directory)
    let original = try reopened.document(for: template)
    let savedDraft = try reopened.document(for: draft)
    #expect(original.page(at: 0)?.annotations.first(where: { $0.fieldName == "date" })?.widgetStringValue == "November 13")
    #expect(savedDraft.page(at: 0)?.annotations.first(where: { $0.fieldName == "date" })?.widgetStringValue == "November 14")
    #expect(savedDraft.page(at: 0)?.annotations.first(where: { $0.fieldName == "checked" })?.buttonWidgetState == .onState)
    #expect(savedDraft.page(at: 0)?.annotations.contains(where: { $0.userName == "MagnumFieldTraining.UserInk" }) == true)
    #expect(reopened.drafts.count == 1 && reopened.templates.count == 1)
    try reopened.rename(draft, to: "Renamed")
    #expect(reopened.drafts.first?.name == "Renamed")
    try reopened.delete(draft)
    #expect(reopened.drafts.isEmpty && reopened.templates.count == 1)
}

@Test @MainActor
func invalidSaveKeepsPreviousDraftAndCorruptFilesAreRetained() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SavedFormStore(directory: directory)
    let draft = try store.save(document: makeForm(), id: UUID(), name: "Original", kind: .draft)
    #expect(throws: (any Error).self) { try store.rename(draft, to: "  ") }
    #expect(SavedFormStore(directory: directory).drafts.first?.name == "Original")
    let corruptURL = directory.appendingPathComponent("corrupt.savedform")
    try Data("invalid".utf8).write(to: corruptURL)
    let reopened = SavedFormStore(directory: directory)
    #expect(reopened.loadError != nil)
    #expect(reopened.drafts.count == 1)
    #expect(FileManager.default.fileExists(atPath: corruptURL.path))
}

@MainActor
private func searchablePDF() throws -> URL {
    let data = NSMutableData()
    let consumer = try #require(CGDataConsumer(data: data))
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    for text in ["Ordinary first page", "Inspect the CAFÉ equipment before use"] {
        context.beginPDFPage(nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 16)]))
        context.textPosition = CGPoint(x: 30, y: 700)
        CTLineDraw(line, context)
        context.endPDFPage()
    }
    context.closePDF()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    try (data as Data).write(to: url)
    return url
}

@Test @MainActor
func contentSearchFindsPageAndExcerptAndHandlesMissingFiles() async throws {
    let url = try searchablePDF()
    defer { try? FileManager.default.removeItem(at: url) }
    let source = PDFSearchSource(resourceID: "document", url: url)
    let result = try await PDFContentSearch.search("cafe", sources: [source])
    #expect(result.matches.count == 1)
    #expect(result.matches.first?.pageIndex == 1)
    #expect(result.matches.first?.excerpt.contains("equipment") == true)
    #expect(result.matches.first?.id == "document:1")
    let empty = try await PDFContentSearch.search("unmatched", sources: [source])
    #expect(empty.matches.isEmpty)
    let missing = try await PDFContentSearch.search("cafe", sources: [PDFSearchSource(resourceID: "missing", url: url.appendingPathExtension("missing"))])
    #expect(missing.unreadableCount == 1)
    let blank = try await PDFContentSearch.search("  ", sources: [source])
    #expect(blank.matches.isEmpty)
}

@Test @MainActor
func contentSearchHonorsCancellation() async throws {
    let task = Task {
        return try await PDFContentSearch.search("query", sources: [])
    }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Cancelled search unexpectedly finished")
    } catch is CancellationError {} catch { Issue.record(error) }
}

@Test @MainActor
func earlierAutomaticFormsStayOutsideSavedFormsUntilAdded() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SavedFormStore(directory: directory)
    let oldDraft = try store.save(document: makeForm(), id: UUID(), name: "Earlier form", kind: .draft)
    let oldTemplate = try store.save(document: makeForm(), id: UUID(), name: "Earlier template", kind: .template)
    // Re-create archives written before explicit addition was recorded.
    for form in [oldDraft, oldTemplate] {
        let url = directory.appendingPathComponent(form.id.uuidString + ".savedform")
        var archive = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var metadata = try #require(archive["form"] as? [String: Any])
        metadata.removeValue(forKey: "wasExplicitlyAdded")
        archive["form"] = metadata
        try JSONSerialization.data(withJSONObject: archive).write(to: url)
    }
    let reopened = SavedFormStore(directory: directory)
    #expect(reopened.drafts.isEmpty)
    #expect(reopened.earlierForms.map(\.id) == [oldDraft.id])
    #expect(reopened.templates.map(\.id) == [oldTemplate.id])
    let earlier = try #require(reopened.earlierForms.first)
    try reopened.rename(earlier, to: "Review later")
    #expect(reopened.drafts.isEmpty)
    #expect(reopened.earlierForms.count == 1)
    let document = try reopened.document(for: earlier)
    document.page(at: 0)?.annotations.first(where: { $0.fieldName == "date" })?.widgetStringValue = "Updated before adding"
    try reopened.save(document: document, id: earlier.id, name: "My Form", kind: .draft)
    let finalStore = SavedFormStore(directory: directory)
    #expect(finalStore.earlierForms.isEmpty)
    let added = try #require(finalStore.drafts.first)
    #expect(added.wasExplicitlyAdded == true)
    #expect(try finalStore.document(for: added).page(at: 0)?.annotations.first(where: { $0.fieldName == "date" })?.widgetStringValue == "Updated before adding")
}

@Test @MainActor
func payrollAndSafetyPDFsOpenInTheEditableFormFlow() {
    let payroll = Program(name: "Payroll", source: .dropbox(path: "/Payroll"))
    let safety = Program(name: "Safety Forms", source: .dropbox(path: "/Safety Forms"))
    let general = Program(name: "Resources", source: .dropbox(path: "/Resources"))
    let file = DropboxFileMetadata(id: "payroll", name: "Timesheet.pdf", pathLower: "/payroll/timesheet.pdf", rev: "1")
    let resource = WalkthroughResource(title: "Timesheet", location: .dropbox(file))
    #expect(payroll.opensInFormEditor(resource))
    #expect(safety.opensInFormEditor(resource))
    #expect(general.opensInFormEditor(resource))
    let video = WalkthroughResource(title: "Training", location: .dropbox(DropboxFileMetadata(id: "video", name: "Training.mp4", pathLower: "/payroll/training.mp4", rev: "1")))
    #expect(!payroll.opensInFormEditor(video))
}

@Test @MainActor
func requestedResourceOrderIsIndependentOfFolderPrefixes() {
    let names = ["Training Resources", "Payroll Forms", "Weekly Safety Topics", "Safety Forms"]
    let programs = names.map { Program(name: $0, source: .dropbox(path: "/" + $0)) }
    #expect(programs.sorted { $0.resourceOrder < $1.resourceOrder }.map(\.name)
            == ["Weekly Safety Topics", "Safety Forms", "Payroll Forms", "Training Resources"])
    #expect(Program(name: "01 Weekly Safety Topics", source: .dropbox(path: "/weekly")).resourceOrder == 0)
    #expect(Program(name: "Other Folder", source: .dropbox(path: "/other")).resourceOrder == 4)
}

@Test @MainActor
func fieldAssistantEditsPersistAndRequiredFlagsUpdate() throws {
    let document = makeForm()
    let field = try #require(FormFieldSupport.fields(in: document).first { $0.name == "date" })
    #expect(field.isDate)
    field.annotation.setValue(NSNumber(value: 2), forAnnotationKey: .widgetFieldFlags)
    FormFieldSupport.setText("", for: field, in: document)
    #expect(field.isMissing)
    FormFieldSupport.setText("11/13/2026", for: field, in: document)
    #expect(!field.isMissing)
    let data = try #require(document.dataRepresentation())
    let reopened = try #require(PDFDocument(data: data))
    #expect(FormFieldSupport.fields(in: reopened).first { $0.name == "date" }?.annotation.widgetStringValue == "11/13/2026")
    #expect(FormFieldSupport.fields(in: reopened).first { $0.name == "date" }?.isRequired == true)
}

@Test @MainActor
func duplicateFieldsRespectReadOnlyAndLengthLimits() throws {
    let document = makeForm()
    let page = try #require(document.page(at: 0))
    let original = try #require(FormFieldSupport.fields(in: document).first { $0.name == "date" })
    let peer = PDFAnnotation(bounds: CGRect(x: 200, y: 300, width: 100, height: 30), forType: .widget, withProperties: nil)
    peer.widgetFieldType = .text
    peer.fieldName = "date"
    page.addAnnotation(peer)
    original.annotation.setValue(NSNumber(value: 4), forAnnotationKey: .widgetMaxLen)
    FormFieldSupport.setText("abcdef", for: original, in: document)
    #expect(original.annotation.widgetStringValue == "abcd")
    #expect(peer.widgetStringValue == "abcd")
    original.annotation.isReadOnly = true
    FormFieldSupport.setText("changed", for: original, in: document)
    #expect(original.annotation.widgetStringValue == "abcd")
    #expect(!original.isDate)
}

@Test @MainActor
func radioChoicesAreExclusiveAndRequiredGroupsAcceptOneSelection() throws {
    let document = makeForm()
    let page = try #require(document.page(at: 0))
    for index in 0..<2 {
        let annotation = PDFAnnotation(bounds: CGRect(x: index * 40, y: 400, width: 20, height: 20), forType: .widget, withProperties: nil)
        annotation.widgetFieldType = .button
        annotation.widgetControlType = .radioButtonControl
        annotation.fieldName = "choice"
        annotation.setValue(NSNumber(value: (1 << 15) | 2), forAnnotationKey: .widgetFieldFlags)
        annotation.buttonWidgetStateString = "Option\(index)"
        annotation.buttonWidgetState = .offState
        page.addAnnotation(annotation)
    }
    let choices = FormFieldSupport.fields(in: document).filter { $0.name == "choice" }
    try #require(choices.count == 2)
    #expect(choices.allSatisfy { $0.isMissing })
    FormFieldSupport.setChecked(true, for: choices[0], in: document)
    #expect(choices.allSatisfy { !$0.isMissing })
    FormFieldSupport.setChecked(true, for: choices[1], in: document)
    #expect(choices[0].annotation.buttonWidgetState == .offState)
    #expect(choices[1].annotation.buttonWidgetState == .onState)
}

@Test @MainActor
func dateUpdatesPreserveNumericOrderAcrossLanguageChanges() throws {
    let date = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 12)))
    #expect(FormFieldSupport.todayValue(replacing: "2025-01-02", date: date, locale: Locale(identifier: "en_US")) == "2026-11-13")
    #expect(FormFieldSupport.todayValue(replacing: "01/02/2025", date: date, locale: Locale(identifier: "es")) == "11/13/2026")
    #expect(FormFieldSupport.todayValue(replacing: "25/02/2025", date: date, locale: Locale(identifier: "en_US")) == "13/11/2026")
    #expect(FormFieldSupport.todayValue(replacing: "01/02/25", date: date, locale: Locale(identifier: "en_US")) == "11/13/26")
}
