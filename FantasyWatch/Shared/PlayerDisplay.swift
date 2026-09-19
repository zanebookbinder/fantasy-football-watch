import Foundation

/// Presentation-only derivations. Anything that would need an ESPN stat id
/// belongs in the Lambda, not here.
extension Player {
    /// What to show beneath the name when the Lambda sent an empty stat line.
    ///
    /// The Lambda deliberately emits "" rather than a row of zeros, leaving the
    /// placeholder wording to the UI.
    var statLineOrPlaceholder: String {
        if !statLine.isEmpty { return statLine }
        switch gameState {
        case .pre: return "— yet to play"
        case .live: return "— no stats yet"
        case .final: return "— did not play"
        }
    }

    var hasPlayed: Bool { gameState != .pre }

    var isOut: Bool {
        guard let injury else { return false }
        return ["OUT", "INJURY_RESERVE", "SUSPENSION", "DOUBTFUL"].contains(injury)
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

extension TeamScore {
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

    /// "as of 30s ago" — the honesty knob on a cached or stale score.
    static func staleness(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
