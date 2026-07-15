import SwiftUI
import UIKit

enum ImportAction: String {
    case upload = "com.jj.ticketlifeline.upload-code"
    case scan = "com.jj.ticketlifeline.scan-code"
}

@MainActor
final class ImportCoordinator: ObservableObject {
    static let shared = ImportCoordinator()

    @Published private(set) var pendingAction: ImportAction?

    func request(_ action: ImportAction) {
        pendingAction = action
    }

    func consumePendingAction() -> ImportAction? {
        defer { pendingAction = nil }
        return pendingAction
    }
}

final class TicketLifelineAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            route(shortcut)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcut = options.shortcutItem {
            route(shortcut)
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = TicketLifelineSceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(route(shortcutItem))
    }

    @discardableResult
    fileprivate func route(_ shortcut: UIApplicationShortcutItem) -> Bool {
        guard let action = ImportAction(rawValue: shortcut.type) else { return false }
        Task { @MainActor in ImportCoordinator.shared.request(action) }
        return true
    }
}

final class TicketLifelineSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let action = ImportAction(rawValue: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        Task { @MainActor in ImportCoordinator.shared.request(action) }
        completionHandler(true)
    }
}
