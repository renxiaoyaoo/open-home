import Foundation

protocol ProviderFactory: Sendable {
    func gateProvider() throws -> any GateProvider
    func dryerProvider() throws -> any HomeProvider<DryerSnapshot>
    func vehicleProvider() throws -> any HomeProvider<VehicleSnapshot>
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

    func dryerProvider() throws -> any HomeProvider<DryerSnapshot> {
        RemoteDryerProvider(client: APIClient(baseURL: baseURL, credential: credential))
    }

    func vehicleProvider() throws -> any HomeProvider<VehicleSnapshot> {
        RemoteVehicleProvider(client: APIClient(baseURL: baseURL, credential: credential))
    }
}

struct DirectProviderFactory: ProviderFactory {
    let registry: DirectProviderRegistry

    func gateProvider() throws -> any GateProvider { try registry.gate() }
    func dryerProvider() throws -> any HomeProvider<DryerSnapshot> { try registry.dryer() }
    func vehicleProvider() throws -> any HomeProvider<VehicleSnapshot> { try registry.vehicle() }
}

struct DirectProviderRegistry: Sendable {
    var gate: @Sendable () throws -> any GateProvider
    var dryer: @Sendable () throws -> any HomeProvider<DryerSnapshot>
    var vehicle: @Sendable () throws -> any HomeProvider<VehicleSnapshot>
    var authenticator: @Sendable (ProviderID) throws -> any DirectProviderAuthenticator

    static let unconfigured = Self(
        gate: { throw ProviderError.notInstalled(.gate) },
        dryer: { throw ProviderError.notInstalled(.living) },
        vehicle: { throw ProviderError.notInstalled(.auto) },
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
private final class DebugDirectAuthenticationState: @unchecked Sendable {
    private let lock = NSLock()
    private var authenticated = false
    func read() -> Bool { lock.withLock { authenticated } }
    func signIn() { lock.withLock { authenticated = true } }
}

private struct DebugDirectAuthenticator: DirectProviderAuthenticator {
    let state: DebugDirectAuthenticationState
    let configuration = DirectLoginConfiguration(methods: [.verificationCode, .password])
    func requestVerificationCode(account: String) async throws {}
    func signIn(account: String, secret: String, method: DirectLoginMethod) async throws -> DirectProviderSession {
        state.signIn()
        return .init(accountID: "debug", displayName: "Preview", credential: Data("debug-session".utf8))
    }
}

private struct DebugGateProvider: GateProvider {
    func resources() async throws -> [GateResource] { [] }
    func open(resourceID: String, idempotencyKey: String) async throws -> OperationResult { .init(ok: true, message: "已打开") }
    func password(resourceID: String) async throws -> GatePassword { .init(password: "0000", validUntil: .now.addingTimeInterval(300)) }
}

extension DirectProviderRegistry {
    static func debugAuthenticationPreview() -> Self {
        let state = DebugDirectAuthenticationState()
        return Self(
            gate: { guard state.read() else { throw ProviderError.authenticationRequired(.gate) }; return DebugGateProvider() },
            dryer: { throw ProviderError.notInstalled(.living) },
            vehicle: { throw ProviderError.notInstalled(.auto) },
            authenticator: { provider in guard provider == .gate else { throw ProviderError.notInstalled(provider) }; return DebugDirectAuthenticator(state: state) }
        )
    }
}
#endif
