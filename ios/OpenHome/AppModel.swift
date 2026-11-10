import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum CenterState: Equatable {
        case disconnected
        case validating
        case connected(CenterSession)
        case unavailable(String)
        case revoked
    }
    enum Module: String, CaseIterable, Identifiable {
        case gate = "OpenGate"
        case living = "OpenLiving"
        case lock = "OpenLock"
        case auto = "OpenAuto"

        var id: Self { self }
        var subtitle: String {
            switch self {
            case .gate: "门禁"
            case .living: "智能家电"
            case .lock: "智能门锁"
            case .auto: "车辆"
            }
        }
        var symbol: String {
            switch self {
            case .gate: "door.left.hand.open"
            case .living: "washer"
            case .lock: "lock.shield"
            case .auto: "car.side"
            }
        }
        var providerID: ProviderID { switch self { case .gate: .gate; case .living: .living; case .lock: .lock; case .auto: .auto } }
    }

    var selectedModule: Module = .gate
    var connection: ConnectionConfiguration?
    var centerState: CenterState = .disconnected
    var sessionRevision = 0
    let directProviders: DirectProviderRegistry

    var enabledModules: [Module] {
        guard let enabled = connection?.enabledProviders else { return [] }
        return Module.allCases.filter { enabled.contains($0.providerID) }
    }

    var availableModules: [Module] {
        guard let connection else { return [] }
        switch connection.mode {
        case .center: return Module.allCases
        case .direct: return Module.allCases.filter { directProviders.installed.contains($0.providerID) }
        }
    }

    init(connectionStore: ConnectionStore = ConnectionStore(), directProviders: DirectProviderRegistry = .unconfigured) {
        connection = connectionStore.load()
        self.directProviders = directProviders
        if connection?.mode == .center { centerState = .validating }
        if let first = Module.allCases.first(where: { connection?.enabledProviders.contains($0.providerID) == true }) { selectedModule = first }
    }

    func setModule(_ module: Module, enabled: Bool, connectionStore: ConnectionStore = ConnectionStore()) throws {
        guard let current = connection, availableModules.contains(module) else { return }
        var providers = current.enabledProviders
        if enabled { providers.insert(module.providerID) } else { providers.remove(module.providerID) }
        let updated = ConnectionConfiguration(mode: current.mode, centerURL: current.centerURL, deviceCredentialID: current.deviceCredentialID, enabledProviders: providers)
        try connectionStore.save(updated)
        connection = updated
        if enabled { selectedModule = module }
        else if selectedModule == module, let first = enabledModules.first { selectedModule = first }
    }

    func disconnect(connectionStore: ConnectionStore = ConnectionStore()) {
        connectionStore.clear()
        connection = nil
        centerState = .disconnected
    }

    func disconnectCenter(connectionStore: ConnectionStore = ConnectionStore()) async {
        if let connection, connection.mode == .center, let baseURL = connection.centerURL {
            try? await APIClient(baseURL: baseURL, credential: { try connectionStore.centerToken() }).revokeCenterSession()
        }
        disconnect(connectionStore: connectionStore)
    }

    func validateCenter(connectionStore: ConnectionStore = ConnectionStore()) async {
        guard let connection, connection.mode == .center, let baseURL = connection.centerURL else {
            centerState = .disconnected
            return
        }
        centerState = .validating
        do {
            centerState = .connected(try await APIClient(baseURL: baseURL, credential: { try connectionStore.centerToken() }).centerSession())
        } catch APIError.unauthorized {
            centerState = .revoked
        } catch {
            centerState = .unavailable(error.localizedDescription)
        }
    }

    func signOutSelectedDirectProvider(sessionStore: DirectSessionStore = DirectSessionStore()) throws {
        try sessionStore.remove(provider: selectedModule.providerID)
        sessionRevision += 1
    }

    func providerFactory(connectionStore: ConnectionStore = ConnectionStore()) -> (any ProviderFactory)? {
        guard let connection else { return nil }
        switch connection.mode {
        case .center:
            guard let baseURL = connection.centerURL else { return nil }
            return RemoteProviderFactory(baseURL: baseURL, credential: { try connectionStore.centerToken() })
        case .direct:
            return DirectProviderFactory(registry: directProviders)
        }
    }
}
