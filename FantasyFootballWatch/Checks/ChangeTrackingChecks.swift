import Foundation

/// Checks for the "what changed since I last looked" rules.
///
/// There is no XCTest target here, so this compiles the shared sources for
/// macOS and asserts against the bundled sample payload. Run it with
/// `make check-watch`.
///
/// The rules it pins down are easy to get subtly wrong: a dot must not appear
/// the first time a player is seen, must survive a refresh the user did not
/// look at, must clear when the row is opened, and must come back if the score
/// moves again.
@main
struct ChangeTrackingChecks {
    static func main() {
        let url = URL(fileURLWithPath: "Shared/sample-payload.json")
        let data = try! Data(contentsOf: url)
        let payload = try! JSONDecoder.fantasy.decode(
            ScorePayload.self, from: data
        )

        MainActor.assumeIsolated { run(payload) }
        checkStandings(payload)
        print("\nAll checks passed.")
    }

    /// This week's scoring rank and the season standings are different facts
    /// that once shared a line and read as one: two 1-0 teams showed as "1st"
    /// and "10th place of 10 teams", which looked like a contradiction.
    static func checkStandings(_ payload: ScorePayload) {
        print("Scoring rank and league standing stay separate")
        let me = payload.me!
        let opp = payload.opp!

        check("today's scoring is labelled as today's",
              me.scoringRankText == "1st in scoring this week")
        check("the opponent's scoring rank is their own",
              opp.scoringRankText == "10th in scoring this week")
        check("the season line carries record and seed",
              me.leagueStandingText == "1-0 · 1st in league")
        check("both are 1-0 yet seeded differently",
              opp.leagueStandingText == "1-0 · 3rd in league")
        check("neither line claims the other's meaning",
              !(me.scoringRankText ?? "").contains("league")
                  && !(me.leagueStandingText ?? "").contains("this week"))

        print("Ordinals")
        check("1st/2nd/3rd", Format.ordinal(1) == "1st"
              && Format.ordinal(2) == "2nd" && Format.ordinal(3) == "3rd")
        check("teens are th", Format.ordinal(11) == "11th"
              && Format.ordinal(12) == "12th" && Format.ordinal(13) == "13th")
        check("10th and 21st", Format.ordinal(10) == "10th"
              && Format.ordinal(21) == "21st")
    }

    static func check(_ label: String, _ ok: Bool) {
        print(ok ? "  ok    \(label)" : "  FAIL  \(label)")
        if !ok { exit(1) }
    }

    @MainActor
    static func run(_ payload: ScorePayload) {
        let suite = UserDefaults(suiteName: "checks.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.description) }
        let store = PlayerSnapshotStore(defaults: suite)

        let allen = payload.players.first { $0.name == "Josh Allen" }!
        let yetToPlay = payload.players.first { $0.gameState == .pre }!

        print("A player seen for the first time is not 'changed'")
        check("no dot on first sight", store.change(for: allen) == nil)

        store.reconcile(payload.players)
        check("no dot after the baseline is seeded", store.change(for: allen) == nil)

        print("Scoring produces a dot and a readable delta")
        var scored = allen
        scored.points = 48.52
        scored.stats = ["cmp": 21, "att": 32, "passYd": 255, "passTd": 4,
                        "car": 14, "rushYd": 69, "rushTd": 2]
        let gain = store.change(for: scored)
        check("dot appears", gain != nil)
        check("delta is the points difference",
              String(format: "%+.2f", gain!.points) == "+7.70")
        check("a gain reads as a gain", gain!.isGain)
        check("only the stats that moved are named",
              gain!.statSummary == "1 cmp, 1 att, 7 pass yd, 1 pass TD")

        print("A refresh must not clear a dot nobody looked at")
        store.reconcile([scored])
        check("dot survives", store.change(for: scored) != nil)

        print("Opening the row retires the dot")
        store.acknowledge(scored)
        check("dot cleared", store.change(for: scored) == nil)

        print("The dot returns only when the score moves again")
        var lost = scored
        lost.points = 46.52
        lost.stats = ["cmp": 21, "att": 33, "passYd": 255, "passTd": 4,
                      "car": 14, "rushYd": 69, "rushTd": 2, "int": 1]
        let drop = store.change(for: lost)
        check("dot back", drop != nil)
        check("a drop reads as a loss", drop!.points < 0 && !drop!.isGain)
        check("the losing stat is named", drop!.statSummary.contains("1 INT"))

        print("A player who has not kicked off has nothing to show")
        check("no dot before kickoff", store.change(for: yetToPlay) == nil)

        print("Baselines survive a relaunch, and reset with a team change")
        let reopened = PlayerSnapshotStore(defaults: suite)
        check("reloaded from disk", reopened.change(for: lost) != nil)
        reopened.reset()
        check("nothing carried across teams", reopened.change(for: lost) == nil)
    }
}
