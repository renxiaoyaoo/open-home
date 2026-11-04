import SwiftUI

@main
struct OpenHomeApp: App {
    @State private var appModel: AppModel

    init() {
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
