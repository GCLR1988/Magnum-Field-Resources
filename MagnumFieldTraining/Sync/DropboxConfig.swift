import Foundation

/// Fill these in after creating an app in the Dropbox App Console.
/// Full click-by-click steps are in DROPBOX_SETUP.md at the project root.
///
/// IMPORTANT: this embeds credentials directly in the app so foremen never
/// have to sign in individually. Create the Dropbox app with "App folder"
/// access (not "Full Dropbox") so it can only ever see one dedicated
/// folder -- that way, if these values are ever extracted from the app,
/// the worst case is read access to just that one training folder.
enum DropboxConfig {
    // The organized Dropbox source is now the permanent source for this version.
    // The historical local filename/type is retained to avoid moving credentials.
    // Both Debug and Release use it; previously distributed binaries retain their old source.
    static let appKey = StagingCredentials.appKey
    static let appSecret = StagingCredentials.appSecret
    static let refreshToken = StagingCredentials.refreshToken

    static var isConfigured: Bool {
        #if DEBUG
        // A staging build must never reuse the live app's storage container.
        guard Bundle.main.bundleIdentifier?.hasSuffix(".staging") == true else { return false }
        #endif
        return [appKey, appSecret, refreshToken].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.hasPrefix("YOUR-")
        }
    }
}
