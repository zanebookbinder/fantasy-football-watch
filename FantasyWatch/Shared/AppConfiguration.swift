import Foundation

/// The Lambda endpoint and client key, injected at build time.
///
/// These come from `Config/Secrets.xcconfig`, which is gitignored — the key
/// stays out of source control (design doc, "Endpoint auth").
enum AppConfiguration {
    static let baseURL: URL? = {
        guard let string = infoValue("LambdaBaseURL"), !string.isEmpty else {
            return nil
        }
        return URL(string: string)
    }()

    static let apiKey: String = infoValue("LambdaAPIKey") ?? ""

    static var isConfigured: Bool { baseURL != nil && !apiKey.isEmpty }

    /// URL scheme the widget deep-links into.
    static let deepLinkScheme = "fantasywatch"

    private static func infoValue(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String
        else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
