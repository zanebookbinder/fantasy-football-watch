import Foundation

/// The Lambda's compact payload.
///
/// This mirrors the frozen contract in `docs/sample-payload.json`. The watch
/// never sees an ESPN stat id or cookie — the Lambda has already done that work.
struct ScorePayload: Codable, Equatable, Sendable {
    var state: PayloadState
    var week: Int?
    var updated: Date
    var leagueSize: Int?
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
    /// This week's rank by live score across the whole league.
    var rank: Int?
    var record: String?
    var seed: Int?
    /// Starters who have not kicked off, are mid-game, and are finished.
    var toPlay: Int?
    var playing: Int?
    var done: Int?
    /// Projected points the yet-to-play starters are still expected to add.
    var remaining: Double?
}

struct Player: Codable, Equatable, Identifiable, Sendable {
    /// ESPN's player id, stable across weeks and roster moves.
    var playerId: Int
    var name: String
    var slot: String
    var position: String
    var proTeam: String
    var gameState: GameState
    var points: Double
    var projected: Double?
    var statLine: String
    /// "@SF" on the road, "NE" at home, nil when the scoreboard had nothing.
    var opponent: String?
    /// Kickoff in UTC; rendered in the wearer's own timezone.
    var kickoff: Date?
    /// "Q3 4:12" while the game is in progress.
    var clock: String?
    var injury: String?
    var side: Side
    /// The same numbers as `statLine`, unformatted, so the watch can work out
    /// what changed since it last looked.
    var stats: [String: Double]?

    /// A player can appear on both rosters in theory, so identity is the id
    /// paired with the side it is listed on.
    var id: String { "\(side.rawValue)-\(playerId)" }

    private enum CodingKeys: String, CodingKey {
        case playerId = "id"
        case name, slot, position, proTeam, gameState, points, projected
        case statLine, opponent, kickoff, injury, side, stats
    }
}

/// One team in the league, as offered by the "my team" picker.
struct LeagueTeam: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var name: String
    var abbrev: String?
    var record: String?
    var seed: Int?
}

struct TeamsPayload: Codable, Equatable, Sendable {
    var state: PayloadState
    var teams: [LeagueTeam]
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
