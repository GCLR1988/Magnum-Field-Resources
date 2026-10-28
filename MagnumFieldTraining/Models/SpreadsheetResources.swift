import Foundation

struct EmployeeContact: Identifiable, Codable, Hashable {
    let name: String
    let email: String
    let phone: String

    var id: String { [name, email, phone].joined(separator: "\u{001F}") }
    var initial: String { String(name.prefix(1)).uppercased() }

    var phoneURL: URL? {
        let allowed = CharacterSet(charactersIn: "+0123456789 ()-.")
        guard phone.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        let digits = phone.filter { $0.isASCII && $0.isNumber }
        guard digits.count >= 3 else { return nil }
        return URL(string: "tel:" + (phone.hasPrefix("+") ? "+" : "") + digits)
    }

    var emailURL: URL? {
        guard email.contains("@"), !email.contains(where: { $0.isWhitespace }) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        return components.url
    }

    func matches(_ query: String) -> Bool {
        let text = [name, email, phone].joined(separator: " ")
        if text.localizedStandardContains(query) { return true }
        let digits = query.filter { $0.isASCII && $0.isNumber }
        return !digits.isEmpty && query.allSatisfy { $0.isNumber || " +()-.".contains($0) }
            && phone.filter { $0.isASCII && $0.isNumber }.contains(digits)
    }
}

struct UsefulLink: Identifiable, Codable, Hashable {
    let title: String
    let url: URL
    var id: String { title + "\u{001F}" + url.absoluteString }

    static func websiteURL(_ value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }) else { return nil }
        let candidate = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, host.contains("."), url.user == nil, url.password == nil else { return nil }
        return url
    }
}

enum SpreadsheetResources {
    static func contacts(from url: URL) throws -> [EmployeeContact] {
        let table = try table(in: url, headers: ["name", "email", "phone"], aliases: [
            "full name": "name",
            "email address": "email",
            "e-mail address": "email",
            "e-mail": "email",
            "phone number": "phone"
        ])
        var seen = Set<String>()
        var contacts: [EmployeeContact] = []
        for row in table.rows {
            let name = row[table.columns["name"] ?? ""] ?? ""
            let email = row[table.columns["email"] ?? ""] ?? ""
            let phone = row[table.columns["phone"] ?? ""] ?? ""
            if name.isEmpty && email.isEmpty && phone.isEmpty { continue }
            guard !name.isEmpty else {
                throw SpreadsheetError.invalid("A directory row has contact details but no Name. Add a name and sync again.")
            }
            let contact = EmployeeContact(name: name, email: email, phone: phone)
            if seen.insert(contact.id).inserted { contacts.append(contact) }
        }
        return contacts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func links(from url: URL) throws -> [UsefulLink] {
        let table = try table(in: url, headers: ["display name", "url"])
        var seen = Set<String>()
        var links: [UsefulLink] = []
        for row in table.rows {
            let title = row[table.columns["display name"] ?? ""] ?? ""
            let column = table.columns["url"] ?? ""
            let value = row[column + ":url"] ?? row[column] ?? ""
            if title.isEmpty && value.isEmpty { continue }
            guard !title.isEmpty, let url = UsefulLink.websiteURL(value) else {
                throw SpreadsheetError.invalid("Each useful link needs a Display Name and a valid website URL. Check the spreadsheet and sync again.")
            }
            let link = UsefulLink(title: title, url: url)
            if seen.insert(link.id).inserted { links.append(link) }
        }
        return links
    }

    private static func table(in url: URL, headers: Set<String>, aliases: [String: String] = [:]) throws
        -> (columns: [String: String], rows: [[String: String]]) {
        let workbook = try ExcelWorkbook(url: url)
        for sheet in workbook.sheets {
            for (index, row) in sheet.rows.prefix(20).enumerated() {
                var columns: [String: String] = [:]
                for (column, value) in row where !column.contains(":") {
                    let heading = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    columns[aliases[heading] ?? heading] = column
                }
                if headers.isSubset(of: Set(columns.keys)) {
                    return (columns, Array(sheet.rows.dropFirst(index + 1)))
                }
            }
        }
        throw SpreadsheetError.invalid(AppLanguage.string("Missing spreadsheet columns: \(headers.sorted().joined(separator: ", ")). Keep the original column headings."))
    }
}
