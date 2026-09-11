import Foundation

/// Exchanges the app's long-lived refresh token for short-lived Dropbox
/// access tokens -- no user sign-in required after the one-time setup in
/// DROPBOX_SETUP.md.
actor DropboxAuthService {
    static let shared = DropboxAuthService()

    private static let formURLEncodedAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    private var cachedToken: String?
    private var expiresAt: Date?
    /// The in-flight refresh, if one is already running -- so concurrent callers
    /// (e.g. syncAll's per-program tasks all hitting an expired token at once)
    /// await the same network round trip instead of each firing their own.
    private var refreshTask: Task<String, Error>?

    func accessToken() async throws -> String {
        if let cachedToken, let expiresAt, expiresAt > Date().addingTimeInterval(60) {
            return cachedToken
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard DropboxConfig.isConfigured else {
            throw DropboxError.notConfigured
        }
        guard let url = URL(string: "https://api.dropboxapi.com/oauth2/token") else {
            throw DropboxError.authFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": DropboxConfig.refreshToken,
            "client_id": DropboxConfig.appKey,
            "client_secret": DropboxConfig.appSecret,
        ]
        request.httpBody = bodyParams
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: Self.formURLEncodedAllowedCharacters) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DropboxError.authFailed
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedToken = decoded.access_token
        expiresAt = Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        return decoded.access_token
    }
}
