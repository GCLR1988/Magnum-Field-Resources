import Foundation
import Testing
@testable import Announcements

private func parse(_ fields: [String: Any] = [:]) throws -> Announcement? {
    var payload: [String: Any] = [
        "id": "notice-1",
        "en": ["title": "Reminder", "message": "Complete training."]
    ]
    payload.merge(fields) { _, new in new }
    return try Announcement.parseJSON(JSONSerialization.data(withJSONObject: payload))
}

@Test func legacyTextAndSnapshotsRemainCompatible() throws {
    #expect(Announcement(text: " \n\t ") == nil)
    let text = try #require(Announcement(text: "\u{FEFF}Title\r\nFirst\r\n\r\nSecond\r\n"))
    #expect(text.title == "Title")
    #expect(text.message == "First\n\nSecond")
    #expect(Announcement(text: "Title")?.message == "")
    let oldSnapshot = Data(#"{"title":"Title","message":"First\n\nSecond"}"#.utf8)
    let decoded = try JSONDecoder().decode(Announcement.self, from: oldSnapshot)
    #expect(decoded == text)
    #expect(decoded.dismissalID == text.dismissalID)
    #expect(Announcement(text: "Changed")?.dismissalID != text.dismissalID)
}

@Test func expirationIsAnAbsoluteOfflineBoundary() throws {
    let notice = try #require(try parse(["expiresAt": "2026-11-20T17:00:00-08:00"]))
    let expiration = try #require(notice.expiresAt)
    #expect(ISO8601DateFormatter().string(from: expiration) == "2026-11-21T01:00:00Z")
    #expect(notice.isVisible(at: expiration.addingTimeInterval(-1), dismissedIDs: []))
    #expect(!notice.isVisible(at: expiration, dismissedIDs: []))
    #expect(!notice.isVisible(at: expiration.addingTimeInterval(1), dismissedIDs: []))
    let cached = try JSONDecoder().decode(Announcement.self, from: JSONEncoder().encode(notice))
    #expect(!cached.isVisible(at: expiration, dismissedIDs: []))
    #expect(try parse(["expiresAt": "2026-11-20T17:00:00.123Z"])?.expiresAt != nil)
    #expect(throws: (any Error).self) { try parse(["expiresAt": "Friday"]) }
    #expect(throws: (any Error).self) { try parse(["expiresAt": "2026-11-20"]) }
}

@Test func dismissalsSurviveRelaunchButNewIDsAppear() throws {
    let notice = try #require(try parse())
    let persisted = try JSONEncoder().encode(Set([notice.dismissalID]))
    let dismissed = try JSONDecoder().decode(Set<String>.self, from: persisted)
    #expect(!notice.isVisible(at: Date(), dismissedIDs: dismissed))
    let correction = try #require(try parse(["en": ["title": "Corrected", "message": "New wording"]]))
    #expect(!correction.isVisible(at: Date(), dismissedIDs: dismissed))
    let newNotice = try #require(try parse(["id": "notice-2"]))
    #expect(newNotice.isVisible(at: Date(), dismissedIDs: dismissed))
}

@Test func languageSelectionAndFallback() throws {
    let notice = try #require(try parse(["es": ["title": "Recordatorio", "message": "Completa la capacitación."]]))
    #expect(notice.translation(for: Locale(identifier: "es-MX")).title == "Recordatorio")
    #expect(notice.translation(for: Locale(identifier: "en")).title == "Reminder")
    #expect(notice.translation(for: Locale(identifier: "fr")).title == "Reminder")
    #expect(try parse()?.translation(for: Locale(identifier: "es")).title == "Reminder")
    #expect(try parse(["es": ["title": " ", "message": ""]])?.translation(for: Locale(identifier: "es")).title == "Reminder")
}

@Test func optionalLinksAndInvalidPublishingData() throws {
    #expect(try parse()?.link == nil)
    #expect(try parse(["link": "https://example.com/training.pdf"])?.link?.path == "/training.pdf")
    for link in ["javascript:alert(1)", "file:///tmp/file", "https:///", "relative/path", "https://user:pass@example.com"] {
        #expect(throws: (any Error).self) { try parse(["link": link]) }
    }
    #expect(try parse(["enabled": false]) == nil)
    #expect(throws: (any Error).self) { try parse(["id": " "]) }
    #expect(throws: (any Error).self) { try parse(["en": ["title": "", "message": "Text"]]) }
    #expect(throws: (any Error).self) { try Announcement.parseJSON(Data("not JSON".utf8)) }
}

@Test func publishingErrorsExplainHowToRepairTheFile() throws {
    do {
        _ = try Announcement.parseJSON(Data("{{\"id\":\"notice\"}".utf8))
        Issue.record("Malformed JSON was accepted")
    } catch {
        #expect(error.localizedDescription.contains("Announcement.json"))
        #expect(error.localizedDescription.contains("quotation marks"))
    }
    do {
        _ = try parse(["en": ["title": "Reminder"]])
        Issue.record("Missing message was accepted")
    } catch {
        #expect(error.localizedDescription.contains("en.message"))
    }
}
