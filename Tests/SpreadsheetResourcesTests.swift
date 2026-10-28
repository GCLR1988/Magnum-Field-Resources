import Foundation
import Testing
@testable import SpreadsheetReader

@Test(.enabled(if: ProcessInfo.processInfo.environment["MAGNUM_DIRECTORY_FIXTURE"] != nil
               && ProcessInfo.processInfo.environment["MAGNUM_LINKS_FIXTURE"] != nil))
func providedWorkbooks() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let directory = environment["MAGNUM_DIRECTORY_FIXTURE"],
          let links = environment["MAGNUM_LINKS_FIXTURE"] else { return }
    let contacts = try SpreadsheetResources.contacts(from: URL(fileURLWithPath: directory))
    #expect(contacts.count == 143)
    #expect(Set(contacts.map(\.id)).count == contacts.count)
    #expect(contacts.allSatisfy { $0.phoneURL?.scheme == "tel" })
    #expect(contacts.allSatisfy { $0.emailURL == nil })
    let websites = try SpreadsheetResources.links(from: URL(fileURLWithPath: links))
    #expect(websites.count == 2)
    #expect(websites.first?.url.scheme == "https")
    #expect(websites.last?.url.host == "www.dropbox.com")
    #expect(websites.last?.url.query?.contains("rlkey=") == true)
}

@Test func contactActionsAndSearch() {
    let contact = EmployeeContact(name: "Example Person", email: "person@example.com", phone: "+1 (555) 010-1234")
    #expect(contact.phoneURL?.absoluteString == "tel:+15550101234")
    #expect(contact.emailURL?.scheme == "mailto")
    #expect(contact.matches("example"))
    #expect(contact.matches("555010"))
    #expect(!contact.matches("unknown"))
    #expect(EmployeeContact(name: "No Phone", email: "", phone: "N/A").phoneURL == nil)
    #expect(EmployeeContact(name: "No Email", email: "", phone: "").emailURL == nil)
}

@Test func linksOnlyOpenWebsites() {
    #expect(UsefulLink.websiteURL("example.com")?.absoluteString == "https://example.com")
    #expect(UsefulLink.websiteURL(" https://example.com/path?q=1 ")?.query == "q=1")
    #expect(UsefulLink.websiteURL("javascript:alert(1)") == nil)
    #expect(UsefulLink.websiteURL("file:///tmp/test") == nil)
    #expect(UsefulLink.websiteURL("https://user:password@example.com") == nil)
    #expect(UsefulLink.websiteURL("") == nil)
}

@Test func corruptWorkbookFailsCleanly() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
    defer { try? FileManager.default.removeItem(at: url) }
    for contents in [Data(), Data("Not an Excel workbook".utf8), Data(repeating: 0, count: 500)] {
        try contents.write(to: url)
        #expect(throws: (any Error).self) { try ExcelWorkbook(url: url) }
    }
}

@Test func wrongHeadersAreRejected() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
    defer { try? FileManager.default.removeItem(at: url) }
    try workbook(rows: [["Display Name", "URL"], ["Example", "https://example.com"]]).write(to: url)
    #expect(throws: (any Error).self) {
        try SpreadsheetResources.contacts(from: url)
    }
}

@Test func revisedDirectoryHeadersIncludeEmail() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
    defer { try? FileManager.default.removeItem(at: url) }
    try workbook(rows: [
        ["Full Name", "e-mail address", "phone number"],
        ["Example Person", "person@example.com", "(555) 010-1234"]
    ]).write(to: url)
    let contacts = try SpreadsheetResources.contacts(from: url)
    #expect(contacts.count == 1)
    #expect(contacts.first?.name == "Example Person")
    #expect(contacts.first?.email == "person@example.com")
    #expect(contacts.first?.emailURL?.scheme == "mailto")
    #expect(contacts.first?.phone == "(555) 010-1234")
}
