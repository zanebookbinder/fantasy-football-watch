import Foundation
import os

/// Talks to the Lambda. Nothing here knows about ESPN.
actor FantasyClient {
    static let shared = FantasyClient()

    enum ClientError: LocalizedError {
        case notConfigured
        case badResponse(Int)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Set LAMBDA_BASE_URL and CLIENT_API_KEY in Config/Secrets.xcconfig."
            case .badResponse(let code):
                return "The score service returned \(code)."
            case .transport:
                return "Couldn't reach the score service."
            }
        }
    }

    private let session: URLSession
    private let store: LastGoodStore
    private let log = Logger(subsystem: "FantasyFootballWatch", category: "client")

    init(session: URLSession? = nil, store: LastGoodStore = .shared) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            // A watch radio that is going to fail should fail fast, so the UI
            // can fall back to the last-good score rather than spin.
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
        self.store = store
    }

    /// Fetch the matchup for a team, persisting it as the last-good payload.
    ///
    /// Omitting `teamId` leaves the choice to the Lambda's configured default,
    /// which is what the widget falls back to before a team has been picked.
    func fetchScore(teamId: Int? = nil) async throws -> ScorePayload {
        var query: [URLQueryItem] = []
        if let teamId {
            query.append(URLQueryItem(name: "teamId", value: String(teamId)))
        }
        let data = try await get(path: "score", query: query)

        let payload = try JSONDecoder.fantasy.decode(ScorePayload.self, from: data)
        if payload.state == .ok {
            await store.save(payload)
        }
        return payload
    }

    /// Every team in the league, for the "my team" picker.
    func fetchTeams() async throws -> [LeagueTeam] {
        let data = try await get(path: "teams", query: [])
        return try JSONDecoder.fantasy.decode(TeamsPayload.self, from: data).teams
    }

    private func get(path: String, query: [URLQueryItem]) async throws -> Data {
        guard let baseURL = AppConfiguration.baseURL, AppConfiguration.isConfigured
        else { throw ClientError.notConfigured }

        var components = URLComponents(
            url: baseURL.appending(path: path), resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw ClientError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(AppConfiguration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 502 still carries a decodable state body; anything else does not.
        guard status == 200 || status == 502 else {
            throw ClientError.badResponse(status)
        }
        return data
    }

    /// The most recent successful payload, for offline and cold widget loads.
    func lastGood() async -> ScorePayload? {
        await store.load()
    }
}

/// Disk-backed last-good payload, so a watch that is offline shows the last
/// score it saw with an honest `updated` timestamp rather than an error.
actor LastGoodStore {
    static let shared = LastGoodStore()

    private let url: URL?
    private var memo: ScorePayload?

    init(filename: String = "last-good-score.json") {
        let directory = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first
        self.url = directory?.appending(path: filename)
    }

    func save(_ payload: ScorePayload) {
        memo = payload
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func load() -> ScorePayload? {
        if let memo { return memo }
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        memo = try? JSONDecoder.fantasy.decode(ScorePayload.self, from: data)
        return memo
    }
}
