import SwiftUI

@main
struct FantasyWatchApp: App {
    @State private var model = MatchupModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MatchupView(model: model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    model.handle(scenePhase: phase)
                }
                .onOpenURL { url in
                    // Tapping the Smart Stack widget lands here; the full
                    // breakdown is always my own lineup.
                    guard url.scheme == AppConfiguration.deepLinkScheme else { return }
                    model.side = .me
                    Task { await model.refresh() }
                }
        }
    }
}
