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
        var tabTitle: String {
            switch self {
            case .gate: "门禁"
            case .living: "家电"
            case .lock: "门锁"
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

    var selectedModule: Module = .gate { didSet { UserDefaults.standard.set(selectedModule.rawValue, forKey: "openhome.selected-module") } }
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
        let saved = UserDefaults.standard.string(forKey: "openhome.selected-module").flatMap(Module.init(rawValue:))
        if let preferred = saved, connection?.enabledProviders.contains(preferred.providerID) == true { selectedModule = preferred }
        else if let first = Module.allCases.first(where: { connection?.enabledProviders.contains($0.providerID) == true }) { selectedModule = first }
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

    func validateCenter(deviceName: String? = nil, connectionStore: ConnectionStore = ConnectionStore()) async {
        guard let connection, connection.mode == .center, let baseURL = connection.centerURL else {
            centerState = .disconnected
            return
        }
        centerState = .validating
        let client = APIClient(baseURL: baseURL, credential: { try connectionStore.centerToken() })
        do {
            let trimmed = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { try? await client.updateCenterDeviceName(trimmed) }
            centerState = .connected(try await client.centerSession())
        } catch APIError.unauthorized {
            centerState = .revoked
        } catch {
            centerState = .unavailable(error.localizedDescription)
        }
    }

    func discardModuleCache(_ provider: ProviderID, blockReload: Bool = true) {
        let file: String
        switch provider {
        case .gate: file = "gate-resources.json"
        case .living: file = "dryer.json"
        case .lock: file = "lock.json"
        case .auto: file = "vehicle.json"
        }
        if blockReload { ModuleContentStore.block(file) } else { ModuleContentStore.remove(file) }
        sessionRevision += 1
    }

    func restoreModule(_ provider: ProviderID) {
        switch provider {
        case .gate: ModuleContentStore.unblock("gate-resources.json")
        case .living: ModuleContentStore.unblock("dryer.json")
        case .lock: ModuleContentStore.unblock("lock.json")
        case .auto: ModuleContentStore.unblock("vehicle.json")
        }
        sessionRevision += 1
    }

    func signOutSelectedDirectProvider(sessionStore: DirectSessionStore = DirectSessionStore()) throws {
        try sessionStore.remove(provider: selectedModule.providerID)
        discardModuleCache(selectedModule.providerID)
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

enum ModuleContentStore {
    private(set) static var revision = 0
    private static var blocked: Set<String> = []
    static func isBlocked(_ name: String) -> Bool { blocked.contains(name) }
    static func block(_ name: String) { blocked.insert(name); remove(name) }
    static func unblock(_ name: String) { blocked.remove(name) }
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenHomeCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ name: String, _ value: T) {
        let seen = revision
        guard !blocked.contains(name) else { return }
        guard let data = try? JSONEncoder().encode(value) else { return }
        guard seen == revision, !blocked.contains(name) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    static func remove(_ name: String) {
        revision += 1
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}
