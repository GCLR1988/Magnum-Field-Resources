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
    static let appKey = "xsbnsf5crixbv9f"
    static let appSecret = "zgbb00vik775fzb"
    /// Long-lived refresh token obtained via the one-time authorization in
    /// DROPBOX_SETUP.md. Doesn't expire on its own (unless revoked).
    static let refreshToken = "A1JsR2zb5G8AAAAAAAAAAWE7t2k33hCuImeljvMc1gLtSiF2k-sWn89vqdsQ_4_-"

    static var isConfigured: Bool {
        !appKey.hasPrefix("YOUR-") && !appSecret.hasPrefix("YOUR-") && !refreshToken.hasPrefix("YOUR-")
    }
}
