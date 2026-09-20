import Foundation

/// Settings that outlive a launch and are shared with the widget extension.
///
/// The app and the widget are separate processes, so the chosen team has to
/// live in an App Group container for both to see it. If the group is
/// unavailable the store falls back to the process's own defaults: the app
/// still works, the widget just falls back to the Lambda's default team.
enum Preferences {
    static let appGroup = "group.com.zanebookbinder.FantasyFootballWatch"

    private static let selectedTeamKey = "selectedTeamId"
    private static let selectedTeamNameKey = "selectedTeamName"

    static let store: UserDefaults =
        UserDefaults(suiteName: appGroup) ?? .standard

    /// The team whose matchup to show, or nil until one has been picked.
    static var selectedTeamId: Int? {
        get {
            let value = store.integer(forKey: selectedTeamKey)
            return value == 0 ? nil : value
        }
        set {
            if let newValue {
                store.set(newValue, forKey: selectedTeamKey)
            } else {
                store.removeObject(forKey: selectedTeamKey)
            }
        }
    }

    /// Remembered so the settings row can name the team without a fetch.
    static var selectedTeamName: String? {
        get { store.string(forKey: selectedTeamNameKey) }
        set { store.set(newValue, forKey: selectedTeamNameKey) }
    }

    static var hasChosenTeam: Bool { selectedTeamId != nil }

    static func select(_ team: LeagueTeam) {
        selectedTeamId = team.id
        selectedTeamName = team.name
    }
}
