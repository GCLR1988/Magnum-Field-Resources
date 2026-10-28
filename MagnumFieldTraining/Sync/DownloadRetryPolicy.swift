import Foundation

enum DownloadRetryPolicy {
    struct TemporaryHTTPError: LocalizedError {
        let status: Int
        let retryAfter: Double?

        var errorDescription: String? {
            "The download service is temporarily unavailable (HTTP \(status)). Please retry."
        }
    }

    /// At most two retries. Authentication, missing files, disk errors and cancellation aren't retried.
    static func delay(for error: Error, attempt: Int) -> Double? {
        guard attempt < 2, !(error is CancellationError) else { return nil }
        if let http = error as? TemporaryHTTPError {
            let delay = max(Double(1 << attempt), http.retryAfter ?? 0)
            // Do not retry sooner than the server requests; let the user retry long delays.
            return delay <= 30 ? delay : nil
        }
        if let urlError = error as? URLError,
           [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(urlError.code) {
            return Double(1 << attempt)
        }
        return nil
    }
}
