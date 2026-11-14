import Foundation
import CryptoKit

/// Publisher-supplied content. Optional fields preserve older offline snapshots.
struct Announcement: Codable, Equatable {
    struct Translation: Codable, Equatable {
        let title: String
        let message: String
    }

    let title: String
    let message: String
    var id: String?
    var expiresAt: Date?
    var link: URL?
    var spanish: Translation?

    var dismissalID: String {
        if let id { return "published:" + id }
        // Legacy text files have no ID, so changing their content publishes a new notice.
        let digest = SHA256.hash(data: Data((title + "\n" + message).utf8))
        return "text:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    func isVisible(at date: Date, dismissedIDs: Set<String>) -> Bool {
        !dismissedIDs.contains(dismissalID) && (expiresAt.map { date < $0 } ?? true)
    }

    func translation(for locale: Locale) -> Translation {
        if locale.language.languageCode?.identifier == "es", let spanish { return spanish }
        return Translation(title: title, message: message)
    }

    init?(text: String) {
        let normalized = Self.normalized(text)
        guard !normalized.isEmpty else { return nil }
        let lines = normalized.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        title = String(lines[0]).trimmingCharacters(in: .whitespaces)
        message = lines.count > 1
            ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
    }

    /// JSON is a separate publishing format; snapshot Codable retains its existing date encoding.
    static func parseJSON(_ data: Data) throws -> Announcement? {
        struct Payload: Decodable {
            let id: String
            let enabled: Bool?
            let expiresAt: String?
            let link: String?
            let en: Translation
            let es: Translation?
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch DecodingError.keyNotFound(let key, let context) {
            let path = (context.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")
            throw FormatError.invalid("Announcement.json is missing the required field: " + path + ".")
        } catch {
            throw FormatError.invalid("Announcement.json is not valid. Check its braces, commas, straight quotation marks, and field types.")
        }
        let id = normalized(payload.id)
        guard !id.isEmpty, !normalized(payload.en.title).isEmpty else {
            throw FormatError.invalid("Announcement id and English title must not be empty.")
        }
        var result = Announcement(title: normalized(payload.en.title), message: normalized(payload.en.message),
                              id: id, expiresAt: nil, link: nil, spanish: nil)
        if let rawDate = payload.expiresAt {
            let formatter = ISO8601DateFormatter()
            var date = formatter.date(from: rawDate)
            if date == nil {
                formatter.formatOptions.insert(.withFractionalSeconds)
                date = formatter.date(from: rawDate)
            }
            guard let date else {
                throw FormatError.invalid("expiresAt must be an ISO 8601 date with a time zone.")
            }
            result.expiresAt = date
        }
        if let rawLink = payload.link, !normalized(rawLink).isEmpty {
            guard let url = URL(string: normalized(rawLink)),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                throw FormatError.invalid("The announcement link must be an http or https URL.")
            }
            result.link = url
        }
        if let spanish = payload.es, !normalized(spanish.title).isEmpty {
            result.spanish = Translation(title: normalized(spanish.title), message: normalized(spanish.message))
        }
        return payload.enabled == false ? nil : result
    }

    private init(title: String, message: String, id: String?, expiresAt: Date?, link: URL?, spanish: Translation?) {
        self.title = title
        self.message = message
        self.id = id
        self.expiresAt = expiresAt
        self.link = link
        self.spanish = spanish
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum FormatError: LocalizedError {
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let message): return message
            }
        }
    }
}
