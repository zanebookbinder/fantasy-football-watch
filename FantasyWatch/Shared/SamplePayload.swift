import Foundation

/// The contract, made concrete.
///
/// `sample-payload.json` is generated from a real captured week by
/// `lambda/tools/sample_payload.py` and bundled into both targets, so previews,
/// the widget placeholder, and the "not configured yet" state all render real
/// data without a network call.
enum SamplePayload {
    static let payload: ScorePayload = {
        guard
            let url = Bundle.main.url(
                forResource: "sample-payload", withExtension: "json"
            ),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder.fantasy.decode(
                ScorePayload.self, from: data
            )
        else { return fallback }
        return decoded
    }()

    /// Used only if the resource is somehow missing from the bundle, so a
    /// preview or placeholder never crashes.
    private static let fallback = ScorePayload(
        state: .ok,
        week: 2,
        updated: Date(),
        me: TeamScore(
            team: "The Christian Faith", live: 47.62, projected: 142.6,
            winProb: 0.69
        ),
        opp: TeamScore(
            team: "Team Tïts", live: -0.1, projected: 108.6, winProb: 0.31
        ),
        players: [
            Player(
                playerId: 3918298,
                name: "Josh Allen", slot: "QB", position: "QB", proTeam: "BUF",
                gameState: .final, points: 40.82, projected: 22.7,
                statLine: "20/31, 248 yd, 3 TD · 14 car, 69 yd, 2 TD",
                opponent: "DET", kickoff: nil, clock: nil,
                injury: nil, side: .me,
                stats: ["cmp": 20, "att": 31, "passYd": 248, "passTd": 3]
            )
        ]
    )
}
