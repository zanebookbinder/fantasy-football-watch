import SwiftUI

@main
struct FantasyFootballWatchApp: App {
    @State private var model = MatchupModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MatchupView(model: model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    model.handle(scenePhase: phase)
                }
                .onOpenURL { url in
                    // Tapping the Smart Stack widget lands here. "?side=opp"
                    // opens straight to the opponent's page; anything else
                    // lands on my own lineup.
                    guard url.scheme == AppConfiguration.deepLinkScheme else { return }
                    let side = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first { $0.name == "side" }?
                        .value
                    model.side = Side(rawValue: side ?? "") ?? .me
                    Task { await model.refresh() }
                }
        }
    }
}
