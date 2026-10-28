import Foundation

struct WebGuide: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let collection: String
    let symbol: String
    let url: URL

    func matches(_ query: String) -> Bool {
        let text = [AppLanguage.string(title), AppLanguage.string(detail), collection].joined(separator: " ")
        return text.localizedStandardContains(query)
    }
}

enum WebGuideCatalog {
    static func guides(for device: AppleDevice) -> [WebGuide] {
        device.guides.map {
            WebGuide(id: "web:apple:\(device.id):\($0.id)", title: $0.title, detail: $0.detail,
                     collection: device.rawValue, symbol: $0.symbol, url: $0.url)
        }
    }

    static func guides(for app: MicrosoftTrainingApp) -> [WebGuide] {
        app.guides.compactMap { guide in
            guard let url = guide.url else { return nil }
            return WebGuide(id: "web:microsoft:\(app.id):\(guide.id)", title: guide.title,
                            detail: guide.detail, collection: app.rawValue, symbol: guide.symbol, url: url)
        }
    }

    static let all: [WebGuide] = AppleDevice.allCases.flatMap { guides(for: $0) }
        + MicrosoftTrainingApp.allCases.flatMap { guides(for: $0) }
}
