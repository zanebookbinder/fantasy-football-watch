import WidgetKit

struct ScoreEntry: TimelineEntry {
    let date: Date
    let payload: ScorePayload
    /// True when this entry is the bundled sample rather than live data.
    var isPlaceholder = false

    /// Raised while a starter is mid-game so the Smart Stack floats this to the
    /// top when it matters, and lowered the rest of the week.
    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: payload.isLive ? 80 : 10)
    }
}

/// Widgets cannot poll — watchOS decides when to reload, on a limited daily
/// budget. So this asks for a short refresh and leans on relevance to be shown
/// when it matters (design doc, "Widget timeline").
struct ScoreProvider: TimelineProvider {
    /// Requested cadence during games. watchOS honours this only within budget,
    /// so treat the widget as a frequently-updated glance, not a live ticker.
    private static let gameDayRefresh: TimeInterval = 15 * 60
    private static let quietRefresh: TimeInterval = 60 * 60

    /// The bundled sample, used for the gallery and as a last resort.
    static var placeholderEntry: ScoreEntry {
        ScoreEntry(
            date: .now, payload: SamplePayload.payload, isPlaceholder: true
        )
    }

    func placeholder(in context: Context) -> ScoreEntry {
        Self.placeholderEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (ScoreEntry) -> Void) {
        if context.isPreview {
            completion(Self.placeholderEntry)
            return
        }
        Task {
            completion(await currentEntry())
        }
    }

    func getTimeline(
        in context: Context, completion: @escaping (Timeline<ScoreEntry>) -> Void
    ) {
        Task {
            let entry = await currentEntry()
            let interval = entry.payload.isLive
                ? Self.gameDayRefresh
                : Self.quietRefresh
            completion(
                Timeline(
                    entries: [entry],
                    policy: .after(.now.addingTimeInterval(interval))
                )
            )
        }
    }

    /// Fresh if the Lambda answers; otherwise the last score this device saw,
    /// which beats a blank tile on a watch that briefly lost its radio.
    private func currentEntry() async -> ScoreEntry {
        let client = FantasyClient.shared
        if let payload = try? await client.fetchScore(), payload.state == .ok {
            return ScoreEntry(date: .now, payload: payload)
        }
        if let cached = await client.lastGood() {
            return ScoreEntry(date: .now, payload: cached)
        }
        return Self.placeholderEntry
    }
}

extension ScorePayload {
    /// Any starter mid-game — used to decide both the refresh cadence and how
    /// hard the Smart Stack should push this widget up the pile.
    var isLive: Bool {
        players.contains { $0.gameState == .live }
    }

    /// Highest-scoring starter on my side, for the rectangular family's
    /// second line.
    var topScorer: Player? {
        lineup(for: .me).max { $0.points < $1.points }
    }
}
