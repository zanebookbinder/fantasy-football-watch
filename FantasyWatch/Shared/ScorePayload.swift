import Foundation

/// The Lambda's compact payload.
///
/// This mirrors the frozen contract in `docs/sample-payload.json`. The watch
/// never sees an ESPN stat id or cookie — the Lambda has already done that work.
struct ScorePayload: Codable, Equatable, Sendable {
    var state: PayloadState
    var week: Int?
    var updated: Date
    var me: TeamScore?
    var opp: TeamScore?
    var players: [Player]

    /// Both lineups arrive in one payload, so flipping to the opponent's team
    /// costs no extra request.
    func lineup(for side: Side) -> [Player] {
        players.filter { $0.side == side }
    }

    /// A copy in a different state, for previewing the error surfaces.
    func with(state: PayloadState) -> ScorePayload {
        var copy = self
        copy.state = state
        return copy
    }
}

/// Decoded leniently: an unrecognised state from a newer Lambda degrades to
/// `upstreamError` rather than failing the whole decode.
enum PayloadState: String, Codable, Sendable {
    case ok
    case authExpired = "auth_expired"
    case upstreamError = "upstream_error"
    case noMatchup = "no_matchup"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PayloadState(rawValue: raw) ?? .upstreamError
    }
}

enum Side: String, Codable, Sendable {
    case me
    case opp
}

struct TeamScore: Codable, Equatable, Sendable {
    var team: String
    var live: Double
    var projected: Double?
    var winProb: Double?
}

struct Player: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var slot: String
    var position: String
    var proTeam: String
    var gameState: GameState
    var points: Double
    var projected: Double?
    var statLine: String
    var injury: String?
    var side: Side

    /// The payload carries no player id, and a lineup can hold the same name on
    /// both sides, so identity is the slot the player occupies.
    var id: String { "\(side.rawValue)-\(slot)-\(name)" }
}

/// Derived in the Lambda from the public NFL scoreboard, so "yet to play" is
/// real rather than inferred from a 0.0.
enum GameState: String, Codable, Sendable {
    case pre
    case live
    case final

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GameState(rawValue: raw) ?? .pre
    }
}

extension JSONDecoder {
    /// The one decoder configuration that matches the contract.
    static var fantasy: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
