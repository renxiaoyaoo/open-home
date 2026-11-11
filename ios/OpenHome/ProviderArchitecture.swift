import Foundation

protocol ProviderFactory: Sendable {
    func gateProvider() throws -> any GateProvider
    func dryerProvider() throws -> any DryerProvider
    func vehicleProvider() throws -> any VehicleProvider
    func lockProvider() throws -> any LockProvider
    func liveActivityRegistrar() -> (any LiveActivityRegistrar)?
}

protocol LiveActivityRegistrar: Sendable {
    func register(activityID: String, provider: ProviderID, resourceID: String, pushToken: Data) async throws
    func unregister(activityID: String) async
}

enum DirectLoginMethod: String, CaseIterable, Identifiable, Sendable {
    case verificationCode
    case password

    var id: Self { self }
    var title: String { self == .verificationCode ? "验证码" : "密码" }
}

struct DirectLoginConfiguration: Sendable {
    let methods: [DirectLoginMethod]
    let accountLabel: String

    init(methods: [DirectLoginMethod], accountLabel: String = "手机号") {
        self.methods = methods
        self.accountLabel = accountLabel
    }
}

struct DirectProviderSession: Codable, Sendable {
    let accountID: String
    let displayName: String?
    let credential: Data
}

struct DirectSessionStore: Sendable {
    private let keychain = KeychainStore()
    private func account(_ provider: ProviderID) -> String { "direct-provider.\(provider.rawValue)" }
    func save(_ session: DirectProviderSession, provider: ProviderID) throws { try keychain.save(JSONEncoder().encode(session), account: account(provider)) }
    func load(provider: ProviderID) throws -> DirectProviderSession? {
        guard let data = try keychain.read(account: account(provider)) else { return nil }
        return try JSONDecoder().decode(DirectProviderSession.self, from: data)
    }
    func remove(provider: ProviderID) throws { try keychain.delete(account: account(provider)) }
}

protocol DirectProviderAuthenticator: Sendable {
    var configuration: DirectLoginConfiguration { get }
    func requestVerificationCode(account: String) async throws
    func signIn(account: String, secret: String, method: DirectLoginMethod) async throws -> DirectProviderSession
}

struct RemoteProviderFactory: ProviderFactory {
    let baseURL: URL
    let credential: @Sendable () throws -> String

    func gateProvider() throws -> any GateProvider {
        RemoteGateProvider(client: APIClient(baseURL: baseURL, credential: credential))
    }

    func dryerProvider() throws -> any DryerProvider {
        RemoteDryerProvider(client: APIClient(baseURL: baseURL, credential: credential))
    }

    func vehicleProvider() throws -> any VehicleProvider {
        RemoteVehicleProvider(client: APIClient(baseURL: baseURL, credential: credential))
    }

    func lockProvider() throws -> any LockProvider {
        RemoteLockProvider(client: APIClient(baseURL: baseURL, credential: credential))
    }

    func liveActivityRegistrar() -> (any LiveActivityRegistrar)? {
        RemoteLiveActivityRegistrar(client: APIClient(baseURL: baseURL, credential: credential))
    }
}

struct DirectProviderFactory: ProviderFactory {
    let registry: DirectProviderRegistry
    let sessions = DirectSessionStore()

    func gateProvider() throws -> any GateProvider { try registry.gate(session(.gate)) }
    func dryerProvider() throws -> any DryerProvider { try registry.dryer(session(.living)) }
    func vehicleProvider() throws -> any VehicleProvider { try registry.vehicle(session(.auto)) }
    func lockProvider() throws -> any LockProvider { try registry.lock(session(.lock)) }
    func liveActivityRegistrar() -> (any LiveActivityRegistrar)? { nil }

    private func session(_ provider: ProviderID) throws -> DirectProviderSession {
        guard registry.installed.contains(provider) else { throw ProviderError.notInstalled(provider) }
        guard let session = try sessions.load(provider: provider) else { throw ProviderError.authenticationRequired(provider) }
        return session
    }
}

struct DirectProviderRegistry: Sendable {
    let installed: Set<ProviderID>
    var gate: @Sendable (DirectProviderSession) throws -> any GateProvider
    var dryer: @Sendable (DirectProviderSession) throws -> any DryerProvider
    var vehicle: @Sendable (DirectProviderSession) throws -> any VehicleProvider
    var lock: @Sendable (DirectProviderSession) throws -> any LockProvider
    var authenticator: @Sendable (ProviderID) throws -> any DirectProviderAuthenticator

    static let unconfigured = Self(
        installed: [],
        gate: { _ in throw ProviderError.notInstalled(.gate) },
        dryer: { _ in throw ProviderError.notInstalled(.living) },
        vehicle: { _ in throw ProviderError.notInstalled(.auto) },
        lock: { _ in throw ProviderError.notInstalled(.lock) },
        authenticator: { throw ProviderError.notInstalled($0) }
    )
}

enum ProviderError: LocalizedError {
    case notInstalled(ProviderID)
    case authenticationRequired(ProviderID)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notInstalled: "此直连 Provider 尚未安装"
        case .authenticationRequired: "请先登录"
        case .invalidResponse: "服务返回的数据无法识别"
        }
    }
}

#if DEBUG
private struct DebugDirectAuthenticator: DirectProviderAuthenticator {
    let configuration = DirectLoginConfiguration(methods: [.verificationCode, .password])
    func requestVerificationCode(account: String) async throws {}
    func signIn(account: String, secret: String, method: DirectLoginMethod) async throws -> DirectProviderSession {
        return .init(accountID: "debug", displayName: "Preview", credential: Data("debug-session".utf8))
    }
}

private struct DebugGateProvider: GateProvider {
    func resources() async throws -> [GateResource] { [] }
    func setSelected(resourceID: String, selected: Bool) async throws {}
    func open(resourceID: String, idempotencyKey: String) async throws -> OperationResult { .init(ok: true, message: "已打开") }
    func password(resourceID: String) async throws -> GatePassword { .init(password: "0000", validUntil: .now.addingTimeInterval(300)) }
}

extension DirectProviderRegistry {
    static func debugAuthenticationPreview() -> Self {
        return Self(
            installed: [.gate],
            gate: { _ in DebugGateProvider() },
            dryer: { _ in throw ProviderError.notInstalled(.living) },
            vehicle: { _ in throw ProviderError.notInstalled(.auto) },
            lock: { _ in throw ProviderError.notInstalled(.lock) },
            authenticator: { provider in guard provider == .gate else { throw ProviderError.notInstalled(provider) }; return DebugDirectAuthenticator() }
        )
    }
}
#endif
