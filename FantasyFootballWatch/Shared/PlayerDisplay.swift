import Foundation

/// Presentation-only derivations. Anything that would need an ESPN stat id
/// belongs in the Lambda, not here.
extension Player {
    /// What to show beneath the name.
    ///
    /// The Lambda emits an empty stat line rather than a row of zeros. For a
    /// player who has not kicked off, the kickoff itself is the useful thing to
    /// show — "@SF Sun 1pm" tells you when to care; "yet to play" does not.
    var subtitle: String {
        if !statLine.isEmpty { return statLine }
        if gameState == .pre, let schedule = scheduleText { return schedule }
        switch gameState {
        case .pre: return "yet to play"
        case .live: return "no stats yet"
        case .final: return "did not play"
        }
    }

    /// What the row shows to the right of the stat line: the game clock while
    /// play is live, so you can tell a 12-point third quarter from a 12-point
    /// final.
    var statusText: String? {
        gameState == .live ? clock : nil
    }

    /// "@SF Sun 1pm" / "NE Thu 8:30pm", in the wearer's timezone.
    var scheduleText: String? {
        switch (opponent, kickoff) {
        case let (opponent?, kickoff?):
            return "\(opponent) \(Format.kickoff(kickoff))"
        case let (opponent?, nil):
            return opponent
        case let (nil, kickoff?):
            return Format.kickoff(kickoff)
        default:
            return nil
        }
    }

    /// Points above or below projection, for players whose game has started.
    ///
    /// Meaningless before kickoff — everyone is "under" their projection at
    /// 0.00 — so it is nil until there is a game to judge it against.
    var projectionDelta: Double? {
        guard gameState != .pre, let projected else { return nil }
        return points - projected
    }

    var hasPlayed: Bool { gameState != .pre }

    var isOut: Bool {
        guard let injury else { return false }
        return ["OUT", "INJURY_RESERVE", "SUSPENSION", "DOUBTFUL"].contains(injury)
    }

    /// "J. Allen" — the widget's detail line has room for about that much.
    var shortName: String {
        let parts = name.split(separator: " ")
        guard let first = parts.first, parts.count > 1 else { return name }
        return "\(first.prefix(1)). \(parts.dropFirst().joined(separator: " "))"
    }

    /// "OUT", "Q" — short enough for a watch row.
    var injuryBadge: String? {
        switch injury {
        case "QUESTIONABLE": return "Q"
        case "DOUBTFUL": return "D"
        case "OUT": return "OUT"
        case "INJURY_RESERVE": return "IR"
        case "SUSPENSION": return "SUSP"
        default: return nil
        }
    }
}

extension ScorePayload {
    /// The starter furthest from their projection in either direction, across
    /// both lineups — the single most interesting thing that has happened so
    /// far, and what the widget leads with.
    var biggestSurprise: Player? {
        players
            .filter { $0.projectionDelta != nil }
            .max { abs($0.projectionDelta!) < abs($1.projectionDelta!) }
    }
}

extension TeamScore {
    /// "7 to play" / "3 playing · 4 to play" / "all done" — the context that
    /// makes a live score mean something.
    var progressText: String? {
        guard let toPlay, let playing else { return nil }
        var parts: [String] = []
        if playing > 0 { parts.append("\(playing) live") }
        if toPlay > 0 { parts.append("\(toPlay) to play") }
        return parts.isEmpty ? "all done" : parts.joined(separator: " · ")
    }

    /// "1st of 10" — where this score sits in the league today.
    var rankText: String? {
        guard let rank else { return nil }
        let suffix: String
        switch (rank % 10, rank % 100) {
        case (1, 11), (2, 12), (3, 13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(rank)\(suffix)"
    }

    var winPercentText: String? {
        guard let winProb else { return nil }
        return "\(Int((winProb * 100).rounded()))%"
    }
}

enum Format {
    /// Fantasy points, the way ESPN shows them.
    static func points(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Tighter form for the widget, where every pixel counts.
    static func compactPoints(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func projected(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    /// "Sun 1pm", "Thu 8:30pm" — the minutes are dropped on the hour.
    static func kickoff(_ date: Date) -> String {
        let formatter = DateFormatter()
        let minutes = Calendar.current.component(.minute, from: date)
        formatter.dateFormat = minutes == 0 ? "EEE ha" : "EEE h:mma"
        return formatter.string(from: date)
            .replacingOccurrences(of: "AM", with: "am")
            .replacingOccurrences(of: "PM", with: "pm")
    }

    /// "+18.1" / "-7.2" — always signed, so the direction reads at a glance.
    static func signedDelta(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    /// "as of 30s ago" — the honesty knob on a cached or stale score.
    static func staleness(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
