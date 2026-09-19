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

    private let client: FantasyClient
    private var pollTask: Task<Void, Never>?

    init(client: FantasyClient = .shared) {
        self.client = client
    }

    var lineup: [Player] {
        payload?.lineup(for: side) ?? []
    }

    /// The team whose lineup is on screen, and the other one.
    var focusedTeam: TeamScore? {
        side == .me ? payload?.me : payload?.opp
    }

    var otherTeam: TeamScore? {
        side == .me ? payload?.opp : payload?.me
    }

    func toggleSide() {
        side = side == .me ? .opp : .me
    }

    // MARK: - Polling

    /// Start the foreground loop. Safe to call repeatedly.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
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
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fresh = try await client.fetchScore()
            payload = fresh
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
