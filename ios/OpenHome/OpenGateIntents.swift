import AppIntents
import Foundation

struct OpenGateOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        let items = try await OpenHomeIntentEnvironment.gateProvider().resources()
            .filter(\.selected)
            .sorted { ($0.selected ? 0 : 1, $0.name) < ($1.selected ? 0 : 1, $1.name) }
            .map { gate in
                IntentItem(
                    gate.id,
                    title: LocalizedStringResource(stringLiteral: gate.name),
                    subtitle: gate.communityName.map(LocalizedStringResource.init(stringLiteral:))
                )
            }
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }
}

struct OpenGateIntent: AppIntent {
    static let title: LocalizedStringResource = "打开门禁"
    static let description = IntentDescription("使用当前 OpenHome 中心连接打开指定门禁。")
#if DEBUG
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
#else
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
#endif
    static let openAppWhenRun = false

    @Parameter(title: "门禁", optionsProvider: OpenGateOptionsProvider()) var gateID: String

    func perform() async throws -> some IntentResult {
        _ = try await OpenHomeIntentEnvironment.gateProvider().open(resourceID: gateID, idempotencyKey: UUID().uuidString)
        return .result()
    }
}

struct OpenHomeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenGateIntent(),
            phrases: ["使用 \(.applicationName) 开门"],
            shortTitle: "打开门禁",
            systemImageName: "lock.open"
        )
    }
}

private enum OpenHomeIntentEnvironment {
    static func gateProvider() throws -> any GateProvider {
        let store = ConnectionStore()
        guard let connection = store.load() else { throw OpenHomeIntentError.missingConnection }
        guard connection.mode == .center else { throw OpenHomeIntentError.centerRequired }
        guard connection.enabledProviders.contains(.gate) else { throw OpenHomeIntentError.gateDisabled }
        guard let baseURL = connection.centerURL else { throw OpenHomeIntentError.centerRequired }
        return RemoteGateProvider(client: APIClient(baseURL: baseURL, credential: { try store.centerToken() }))
    }
}

private enum OpenHomeIntentError: LocalizedError {
    case missingConnection, centerRequired, gateDisabled

    var errorDescription: String? {
        switch self {
        case .missingConnection: "快捷指令无法读取 OpenHome 连接配置"
        case .centerRequired: "请先在 OpenHome 中连接中心"
        case .gateDisabled: "请先在 OpenHome 中启用门禁模块"
        }
    }
}
