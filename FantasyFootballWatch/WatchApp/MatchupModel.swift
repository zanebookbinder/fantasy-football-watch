import Foundation
import Observation
import SwiftUI
import WidgetKit

/// Owns the payload and the foreground polling loop.
///
/// Near-live only happens while the app is open; the loop is cancelled the
/// moment the app backgrounds (design doc, "Refresh strategy").
@MainActor
@Observable
final class MatchupModel {
    /// The Lambda caches for ~20s, so polling faster than that just re-reads the
    /// same bytes. 25s sits just past the cache window.
    static let pollInterval: Duration = .seconds(25)

    private(set) var payload: ScorePayload?
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    /// True when what is on screen came from disk rather than the network.
    private(set) var isShowingLastGood = false

    var side: Side = .me

    /// The team whose matchup is being shown, remembered across launches and
    /// shared with the widget.
    private(set) var selectedTeamId: Int? = Preferences.selectedTeamId
    private(set) var selectedTeamName: String? = Preferences.selectedTeamName

    /// Loaded only when the picker is opened.
    private(set) var leagueTeams: [LeagueTeam] = []
    private(set) var isLoadingTeams = false

    /// Which player's row is open, showing what changed since the last look.
    var expandedPlayerId: String?

    let snapshots = PlayerSnapshotStore()

    private let client: FantasyClient
    private var pollTask: Task<Void, Never>?

    init(client: FantasyClient = .shared) {
        self.client = client
    }

    /// Nothing can be shown until a team has been chosen.
    var needsTeamSelection: Bool { selectedTeamId == nil }

    var lineup: [Player] {
        payload?.lineup(for: side) ?? []
    }

    /// Flip to the other roster. Used by the double-tap gesture and by tapping
    /// the page dots.
    func toggleSide() {
        side = side == .me ? .opp : .me
    }

    func team(for side: Side) -> TeamScore? {
        side == .me ? payload?.me : payload?.opp
    }

    /// The team whose lineup is on screen.
    var focusedTeam: TeamScore? { team(for: side) }

    // MARK: - Polling

    /// Show the last score this watch saw, immediately, while the network
    /// catches up. Without this the app opens on a spinner every time even
    /// though it already has a perfectly good score on disk.
    func loadCachedPayload() async {
        guard payload == nil, !needsTeamSelection,
              let cached = await client.lastGood() else { return }
        payload = cached
        isShowingLastGood = true
    }

    /// Start the foreground loop. Safe to call repeatedly.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.loadCachedPayload()
            while !Task.isCancelled {
                await self?.refresh()
                do {
                    try await Task.sleep(for: MatchupModel.pollInterval)
                } catch {
                    return  // cancelled mid-sleep
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard !needsTeamSelection else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fresh = try await client.fetchScore(teamId: selectedTeamId)
            payload = fresh
            // Advance the baseline for everyone with nothing new to show, so
            // only genuinely changed players keep a dot.
            snapshots.reconcile(fresh.players)
            isShowingLastGood = false
            // `auth_expired` / `upstream_error` are states the view renders, not
            // transport errors, so the error banner stays clear.
            errorMessage = nil
            if fresh.state == .ok {
                // Let the Smart Stack pick up whatever the app just learned.
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            await showLastGood(reason: error)
        }
    }

    /// A transient failure should show a slightly stale score, not an error —
    /// the `updated` timestamp in the header keeps that honest.
    private func showLastGood(reason: Error) async {
        if let cached = await client.lastGood() {
            payload = cached
            isShowingLastGood = true
            errorMessage = nil
        } else {
            errorMessage = (reason as? LocalizedError)?.errorDescription
                ?? reason.localizedDescription
        }
    }

    // MARK: - Team selection

    func loadTeams() async {
        guard leagueTeams.isEmpty, !isLoadingTeams else { return }
        isLoadingTeams = true
        defer { isLoadingTeams = false }
        leagueTeams = (try? await client.fetchTeams()) ?? []
    }

    /// Switch teams. Everything on screen belonged to the old team, so the
    /// payload and the change baselines both go with it.
    func select(_ team: LeagueTeam) async {
        let isChange = selectedTeamId != team.id
        Preferences.select(team)
        selectedTeamId = team.id
        selectedTeamName = team.name

        if isChange {
            snapshots.reset()
            payload = nil
            side = .me
            expandedPlayerId = nil
        }
        await refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Changes since last look

    func change(for player: Player) -> PlayerChange? {
        snapshots.change(for: player)
    }

    func isExpanded(_ player: Player) -> Bool {
        expandedPlayerId == player.id
    }

    /// Opening a row counts as seeing the change, which retires the dot until
    /// the player's score moves again.
    func toggleExpanded(_ player: Player) {
        if expandedPlayerId == player.id {
            expandedPlayerId = nil
        } else {
            expandedPlayerId = player.id
            snapshots.acknowledge(player)
        }
    }

#if DEBUG
    /// Preloaded with the bundled sample payload, for SwiftUI previews.
    static func preview(
        _ payload: ScorePayload = SamplePayload.payload, side: Side = .me
    ) -> MatchupModel {
        let model = MatchupModel()
        model.payload = payload
        model.side = side
        return model
    }
#endif

    /// Hook the loop to the scene phase so it runs only in the foreground.
    func handle(scenePhase: ScenePhase) {
        switch scenePhase {
        case .active: startPolling()
        default: stopPolling()
        }
    }
}
