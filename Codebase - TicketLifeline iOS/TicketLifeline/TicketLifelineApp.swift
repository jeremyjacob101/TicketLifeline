import SwiftUI

@main
struct TicketLifelineApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(appState: appState)
        }
    }
}
