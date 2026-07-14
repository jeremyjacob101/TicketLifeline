import SwiftUI

@main
struct TicketLifelineApp: App {
    @UIApplicationDelegateAdaptor(TicketLifelineAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var importCoordinator = ImportCoordinator.shared

    var body: some Scene {
        WindowGroup {
            RootView(appState: appState, importCoordinator: importCoordinator)
        }
    }
}
