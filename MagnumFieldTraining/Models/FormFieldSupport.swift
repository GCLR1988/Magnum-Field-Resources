import Foundation
import PDFKit

/// References the original widget; helper controls edit the same PDF that is saved and shared.
struct FormField: Identifiable {
    let id: String
    let pageIndex: Int
    let annotation: PDFAnnotation

    var name: String {
        if let label = annotation.value(forAnnotationKey: .widgetTextLabelUI) as? String,
           !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label
        }
        let identifier = (annotation.fieldName?.split(separator: ".").last.map(String.init) ?? "")
            .replacingOccurrences(of: "\\[\\d+\\]", with: "", options: .regularExpression)
        // Generated PDF/XFA identifiers are implementation details, not useful field labels.
        if identifier.isEmpty || identifier.range(of: "^[A-Za-z]{1,3}\\d+(?:_\\d+)*$", options: .regularExpression) != nil {
            let number = (Int(id.split(separator: ":").last ?? "") ?? 0) + 1
            return AppLanguage.string("Field \(number)")
        }
        return identifier.replacingOccurrences(of: "_", with: " ")
    }

    var isRequired: Bool {
        let flags = (annotation.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber)?.intValue ?? 0
        return flags & 2 != 0
    }

    var isMissing: Bool {
        guard isRequired, annotation.widgetFieldType != .signature else { return false }
        if annotation.widgetFieldType == .button {
            guard let name = annotation.fieldName, let document = annotation.page?.document else {
                return annotation.buttonWidgetState == .offState
            }
            return !FormFieldSupport.fields(in: document).contains {
                $0.annotation.fieldName == name && $0.annotation.widgetFieldType == .button && $0.annotation.buttonWidgetState != .offState
            }
        }
        return (annotation.widgetStringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isDate: Bool {
        guard annotation.widgetFieldType == .text, !annotation.isReadOnly else { return false }
        let label = name.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        let words = label.lowercased().split { !$0.isLetter }
        return words.contains("date") || words.contains("fecha")
    }

    var options: [(value: String, label: String)] {
        let raw = annotation.value(forAnnotationKey: .widgetOptions) as? [Any] ?? []
        return raw.compactMap { item in
            if let text = item as? String { return (text, text) }
            if let pair = item as? [String], pair.count >= 2 { return (pair[0], pair[1]) }
            return nil
        }
    }
}

enum FormFieldSupport {
    static func fields(in document: PDFDocument) -> [FormField] {
        var result: [FormField] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            // PDFKit returns "Widget" here, while the subtype raw value includes a leading slash.
            let widgets = page.annotations.filter { $0.type == "Widget" }
                .sorted {
                    if $0.bounds.midY != $1.bounds.midY { return $0.bounds.midY > $1.bounds.midY }
                    return $0.bounds.minX < $1.bounds.minX
                }
            for (index, annotation) in widgets.enumerated() {
                if annotation.widgetFieldType == .button && annotation.widgetControlType == .pushButtonControl { continue }
                result.append(FormField(id: "\(pageIndex):\(index)", pageIndex: pageIndex, annotation: annotation))
            }
        }
        return result
    }

    static func setText(_ value: String, for field: FormField, in document: PDFDocument) {
        guard !field.annotation.isReadOnly,
              field.annotation.widgetFieldType == .text || field.annotation.widgetFieldType == .choice else { return }
        let maxLength = (field.annotation.value(forAnnotationKey: .widgetMaxLen) as? NSNumber)?.intValue ?? 0
        let text = maxLength > 0 ? String(value.prefix(maxLength)) : value
        for peer in peers(of: field, in: document) where !peer.annotation.isReadOnly {
            peer.annotation.widgetStringValue = text
        }
    }

    static func setChecked(_ checked: Bool, for field: FormField, in document: PDFDocument) {
        guard !field.annotation.isReadOnly, field.annotation.widgetFieldType == .button else { return }
        let radio = field.annotation.widgetControlType == .radioButtonControl
        let group = peers(of: field, in: document)
        if radio {
            // PDFKit shares the group's value. Clear other choices first so clearing
            // a later widget cannot erase the selection we just made.
            if !checked && !field.annotation.allowsToggleToOff { return }
            for peer in group where !peer.annotation.isReadOnly {
                peer.annotation.buttonWidgetState = .offState
            }
            if checked { field.annotation.buttonWidgetState = .onState }
        } else {
            for peer in group where !peer.annotation.isReadOnly {
                peer.annotation.buttonWidgetState = checked ? .onState : .offState
            }
        }
    }

    private static func peers(of field: FormField, in document: PDFDocument) -> [FormField] {
        guard let name = field.annotation.fieldName, !name.isEmpty else { return [field] }
        return fields(in: document).filter {
            $0.annotation.fieldName == name && $0.annotation.widgetFieldType == field.annotation.widgetFieldType
        }
    }

    // Existing US company forms keep month-first dates across interface language changes.
    // An unambiguous day-first value is preserved. Every replacement is previewed before applying.
    private static func slashFormat(_ value: String, fourDigitYear: Bool) -> String {
        let first = Int(value.split(separator: "/").first ?? "") ?? 0
        return (first > 12 ? "dd/MM/" : "MM/dd/") + (fourDigitYear ? "yyyy" : "yy")
    }

    /// Preserve common numeric formats; otherwise use a localized short date.
    static func todayValue(replacing existing: String, date: Date = Date(), locale: Locale = AppLanguage.locale) -> String {
        let value = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats: [(String, String)] = [
            ("^\\d{4}-\\d{2}-\\d{2}$", "yyyy-MM-dd"),
            ("^\\d{1,2}/\\d{1,2}/\\d{4}$", slashFormat(value, fourDigitYear: true)),
            ("^\\d{1,2}/\\d{1,2}/\\d{2}$", slashFormat(value, fourDigitYear: false))
        ]
        let formatter = DateFormatter()
        formatter.locale = locale
        if let format = formats.first(where: { value.range(of: $0.0, options: .regularExpression) != nil }) {
            formatter.dateFormat = format.1
        } else {
            formatter.dateStyle = .short
        }
        return formatter.string(from: date)
    }
}
