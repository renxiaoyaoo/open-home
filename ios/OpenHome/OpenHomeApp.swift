import SwiftUI
import UIKit

@main
struct OpenHomeApp: App {
    @State private var appModel: AppModel

    init() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        let normal: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .medium)]
        let selected: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .semibold)]
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = normal
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = selected
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
#if DEBUG
        let registry: DirectProviderRegistry = ProcessInfo.processInfo.arguments.contains("--direct-auth-preview") ? .debugAuthenticationPreview() : .unconfigured
#else
        let registry: DirectProviderRegistry = .unconfigured
#endif
        _appModel = State(initialValue: AppModel(directProviders: registry))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
    }
}
