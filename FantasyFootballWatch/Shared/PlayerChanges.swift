import Foundation

/// What a player has done since you last looked at them.
struct PlayerChange: Equatable, Sendable {
    /// Points gained or lost since the last acknowledged snapshot.
    var points: Double
    /// The stat lines that moved, already formatted: "1 rec, 7 yd, 1 TD".
    var statSummary: String

    var isGain: Bool { points >= 0 }
}

/// A remembered reading of one player.
struct PlayerSnapshot: Codable, Equatable, Sendable {
    var points: Double
    var stats: [String: Double]
}

/// Remembers what each player had last time you looked, so the app can mark the
/// ones that moved and say by how much.
///
/// The baseline advances in two situations: when a player is acknowledged (you
/// opened their row and saw the change), and when a player shows no change at
/// all. It deliberately does *not* advance wholesale on launch — doing that
/// would clear a dot you never actually looked at.
@MainActor
final class PlayerSnapshotStore {
    private static let storageKey = "playerSnapshots"

    private var snapshots: [String: PlayerSnapshot]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = Preferences.store) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(
               [String: PlayerSnapshot].self, from: data
           ) {
            snapshots = decoded
        } else {
            snapshots = [:]
        }
    }

    private func id(of player: Player) -> String { String(player.playerId) }

    /// The change to show for this player, or nil when there is nothing new.
    func change(for player: Player) -> PlayerChange? {
        // A player seen for the first time is not "changed" — there is no
        // previous reading to have missed.
        guard let previous = snapshots[id(of: player)] else { return nil }
        guard previous.points != player.points else { return nil }

        return PlayerChange(
            points: player.points - previous.points,
            statSummary: StatDelta.summary(
                from: previous.stats, to: player.stats ?? [:]
            )
        )
    }

    func hasChange(for player: Player) -> Bool { change(for: player) != nil }

    /// Record the current reading, clearing any pending change.
    func acknowledge(_ player: Player) {
        snapshots[id(of: player)] = PlayerSnapshot(
            points: player.points, stats: player.stats ?? [:]
        )
        persist()
    }

    /// Advance the baseline for everyone who has nothing to show, and seed
    /// players never seen before. Players with a pending change are left alone
    /// so their dot survives until it is actually looked at.
    func reconcile(_ players: [Player]) {
        var changed = false
        for player in players where change(for: player) == nil {
            let snapshot = PlayerSnapshot(
                points: player.points, stats: player.stats ?? [:]
            )
            if snapshots[id(of: player)] != snapshot {
                snapshots[id(of: player)] = snapshot
                changed = true
            }
        }
        if changed { persist() }
    }

    /// Switching teams brings a whole new set of players; nothing carried over
    /// should count as "changed since you last looked".
    func reset() {
        snapshots = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Turns the difference between two stat readings into ESPN-style wording.
enum StatDelta {
    /// Ordered to match how a stat line reads, so a delta reads the same way.
    private static let fields: [(key: String, label: String)] = [
        ("cmp", "cmp"), ("att", "att"),
        ("passYd", "pass yd"), ("passTd", "pass TD"), ("int", "INT"),
        ("car", "car"), ("rushYd", "rush yd"), ("rushTd", "rush TD"),
        ("tgt", "tgt"), ("rec", "rec"), ("recYd", "yd"), ("recTd", "TD"),
        ("fum", "FUM"),
        ("fgm", "FG"), ("fga", "FGA"), ("xpm", "XP"), ("xpa", "XPA"),
        ("pa", "PA"), ("sack", "sack"), ("dInt", "INT"), ("fr", "FR"),
        ("blk", "BLK"), ("saf", "SAF"), ("dTd", "TD"),
    ]

    /// "1 rec, 7 yd, 1 TD" — only the stats that actually moved.
    static func summary(
        from previous: [String: Double], to current: [String: Double]
    ) -> String {
        var parts: [String] = []
        for field in fields {
            let delta = (current[field.key] ?? 0) - (previous[field.key] ?? 0)
            guard delta != 0 else { continue }
            parts.append("\(number(delta)) \(field.label)")
        }
        return parts.joined(separator: ", ")
    }

    private static func number(_ value: Double) -> String {
        let rounded = value == value.rounded() ? String(Int(value))
                                               : String(format: "%g", value)
        return value > 0 ? rounded : rounded
    }
}
