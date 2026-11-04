import Foundation

/// A TMDB credential. Accepts either the v3 API key
/// or the v4 read-access token, which TMDB's settings page shows side by side.
public enum TMDBCredential: Equatable, Sendable, CustomStringConvertible {
    case apiKey(String)
    case bearerToken(String)

    /// Returns `nil` for a missing, blank or unexpanded (`$(TMDB_API_KEY)`) value.
    public init?(configuredValue: String?) {
        guard
            let value = configuredValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty, !value.contains("$(")
        else { return nil }
        self = value.hasPrefix("eyJ") ? .bearerToken(value) : .apiKey(value)
    }

    public var description: String { "TMDBCredential(redacted)" }
}
