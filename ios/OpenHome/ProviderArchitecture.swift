import Foundation

protocol ProviderFactory: Sendable {
    func gateProvider() throws -> any GateProvider
    func dryerProvider() throws -> any HomeProvider<DryerSnapshot>
    func vehicleProvider() throws -> any HomeProvider<VehicleSnapshot>
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

    static let unconfigured = Self(
        gate: { throw ProviderError.notInstalled(.gate) },
        dryer: { throw ProviderError.notInstalled(.living) },
        vehicle: { throw ProviderError.notInstalled(.auto) }
    )
}

enum ProviderError: LocalizedError {
    case notInstalled(ProviderID)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notInstalled: "此直连 Provider 尚未安装"
        case .invalidResponse: "服务返回的数据无法识别"
        }
    }
}
