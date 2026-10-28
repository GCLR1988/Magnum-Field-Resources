import SwiftUI

enum AppLanguage {
    static let preferenceKey = "appInterfaceLanguage"
    static let defaultCode = Locale.preferredLanguages.first?.hasPrefix("es") == true ? "es" : "en"

    static var locale: Locale {
        Locale(identifier: UserDefaults.standard.string(forKey: preferenceKey) ?? defaultCode)
    }

    static func string(_ resource: LocalizedStringResource, locale selectedLocale: Locale? = nil) -> String {
        var localized = resource
        localized.locale = selectedLocale ?? locale
        return String(localized: localized)
    }
}

/// Updates language in place, preserving navigation and any form being edited.
struct AppLanguageModifier: ViewModifier {
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.defaultCode

    func body(content: Content) -> some View {
        content.environment(\.locale, Locale(identifier: language))
    }
}

struct AppLanguageToggle: View {
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.defaultCode

    var body: some View {
        Button {
            language = language == "es" ? "en" : "es"
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                Text(verbatim: language == "es" ? "English" : "Español")
                    .font(.subheadline.weight(.medium))
            }
        }
        .accessibilityLabel(language == "es" ? "Switch to English" : "Switch to Spanish")
    }
}
