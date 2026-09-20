import SwiftUI

/// The iPhone half of the app.
///
/// It exists so the watch app can reach the App Store: a watchOS app is
/// distributed inside an iOS archive, and Xcode offers no App Store
/// distribution method for a standalone watch archive. The watch app still runs
/// independently once installed — this is a carrier, not a dependency.
@main
struct FantasyFootballWatchPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            CompanionView()
        }
    }
}
