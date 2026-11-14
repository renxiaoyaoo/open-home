import Foundation

enum ConnectionMode: String, Codable, Sendable {
    case center
    case direct
}

struct ConnectionConfiguration: Codable, Sendable, Equatable {
    let mode: ConnectionMode
    let centerURL: URL?
    let deviceCredentialID: String?
    let enabledProviders: Set<ProviderID>
}

enum ProviderID: String, Codable, CaseIterable, Sendable {
    case gate
    case living
    case lock
    case auto
}

struct GateResource: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let communityName: String?
    let passwordSupported: Bool
    let providerFeatured: Bool
    let selected: Bool
    let refreshedAt: Int64
}

struct GatePassword: Codable, Sendable, Equatable {
    let password: String
    let validUntil: Date
}

struct OperationResult: Codable, Sendable, Equatable {
    let ok: Bool
    let message: String
}

protocol GateProvider: Sendable {
    func resources() async throws -> [GateResource]
    func setSelected(resourceID: String, selected: Bool) async throws
    func open(resourceID: String, idempotencyKey: String) async throws -> OperationResult
    func password(resourceID: String) async throws -> GatePassword
}

protocol HomeProvider<Snapshot>: Sendable {
    associatedtype Snapshot: Sendable
    func snapshot() async throws -> Snapshot
}

struct DryerProgram: Codable, Sendable, Identifiable, Equatable {
    let value: Int
    let name: String
    let group: String
    let minutes: Int
    let description: String?
    let icon: String
    let parameters: [DryerProgramParameter]?
    var id: String { "\(group)|\(value)|\(name)" }
}

struct DryerProgramParameter: Codable, Sendable, Identifiable, Equatable {
    let property: String
    let name: String
    let values: [DryerProgramOption]
    let defaultIndex: Int
    let description: String?
    var id: String { property }
}

struct DryerProgramOption: Codable, Sendable, Identifiable, Equatable {
    let value: Int
    let label: String
    var id: Int { value }
}

enum DryerCommand: Sendable { case start, pause, cancelSchedule, schedule(delayMinutes: Int) }

protocol DryerProvider: HomeProvider where Snapshot == DryerSnapshot {
    func programs() async throws -> [DryerProgram]
    func selectProgram(_ program: DryerProgram) async throws
    func configureProgram(_ program: DryerProgram, parameters: [String: Int]) async throws
    func setPower(_ powered: Bool) async throws
    func command(_ command: DryerCommand) async throws
}

struct LockDevice: Codable, Sendable, Identifiable, Equatable { let id: String; let name: String }
struct LockDetail: Codable, Sendable, Equatable {
    let name: String?
    let wifiName: String?
    let wifiSignal: String?
    let battery: String?
    let cameraBattery: String?
    let batteryUpdatedAt: String?
}
struct LockEvent: Codable, Sendable, Equatable, Identifiable {
    let time: String
    let content: String
    let image: URL?
    var id: String { "\(time)|\(content)" }
}
struct LockCapture: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let time: String
    let type: String?
    let image: URL
    let video: URL?

    private enum CodingKeys: String, CodingKey { case id, time, type, image, video }
    init(id: String, time: String, type: String?, image: URL, video: URL?) {
        self.id = id; self.time = time; self.type = type; self.image = image; self.video = video
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        image = try values.decode(URL.self, forKey: .image)
        video = try values.decodeIfPresent(URL.self, forKey: .video)
        if let text = try? values.decode(String.self, forKey: .time) { time = text }
        else if let number = try? values.decode(Double.self, forKey: .time) { time = String(number) }
        else { time = "" }
    }
}
struct LockPage<Item: Codable & Sendable>: Codable, Sendable { let items: [Item]; let nextCursor: String? }
struct LockTemporaryPassword: Codable, Sendable, Equatable { let password: String; let expiresAt: Date }

protocol LockProvider: Sendable {
    func devices() async throws -> [LockDevice]
    func detail(deviceID: String) async throws -> LockDetail
    func dynamics(deviceID: String, cursor: String?) async throws -> LockPage<LockEvent>
    func securityLogs(deviceID: String, cursor: String?) async throws -> LockPage<LockEvent>
    func operationLogs(deviceID: String, cursor: String?) async throws -> LockPage<LockEvent>
    func captures(deviceID: String, cursor: String?) async throws -> LockPage<LockCapture>
    func createTemporaryPassword(deviceID: String) async throws -> LockTemporaryPassword
}

struct DryerSnapshot: Codable, Sendable, Equatable {
    let deviceID: String
    let name: String
    let state: State
    let programName: String?
    let programID: Int?
    let parameters: [String: Int]
    let remainingMinutes: Int?
    let expectedFinish: Date?

    enum State: String, Codable, Sendable { case off, idle, running, paused, scheduled, finished, fault }
}

struct VehicleSnapshot: Codable, Sendable, Equatable {
    let vehicleID: String
    let name: String
    let state: State
    let chargingState: String?
    let speedKPH: Double?
    let totalRangeKM: Double?
    let batteryPercent: Double?
    let fuelPercent: Double?
    let electricRangeKM: Double?
    let fuelRangeKM: Double?
    let odometerKM: Double?
    let evMileageKM: Double?
    let hevMileageKM: Double?
    let cabinTemperatureC: Double?
    let locationName: String?
    let signalStrength: Int?
    let online: Bool?
    let securityState: String?
    let driveMode: String?
    let okIndicator: Bool?
    let powerOutputKW: Double?
    let engineCoolantC: Double?
    let health: [String: String]?
    let doorsOpen: VehicleCornerState?
    let doorsUnlocked: VehicleCornerState?
    let windowsOpen: VehicleCornerState?
    let hoodOpen: Bool?
    let trunkOpen: Bool?
    let skylightOpen: Bool?
    let tirePressureKPA: VehicleTirePressure?
    let chargingPowerKW: Double?
    let remainingChargeMinutes: Int?
    let updatedAt: Date?

    enum State: String, Codable, Sendable { case parked, ready, driving, charging, fault }
}

struct VehicleCornerState: Codable, Sendable, Equatable { let frontLeft: Bool?; let frontRight: Bool?; let rearLeft: Bool?; let rearRight: Bool? }
struct VehicleTirePressure: Codable, Sendable, Equatable { let frontLeft: Double?; let frontRight: Double?; let rearLeft: Double?; let rearRight: Double? }
struct VehicleEnergyBreakdown: Codable, Sendable, Equatable { let propulsionPercent: Double?; let climatePercent: Double?; let electricalPercent: Double?; let otherPercent: Double? }
struct VehicleEnergyTrendPoint: Codable, Sendable, Equatable, Identifiable {
    let date: String
    let equivalentFuelLitresPer100Km: Double?
    let electricityKwhPer100Km: Double?
    let fuelLitresPer100Km: Double?
    let peerAverageLitresPer100Km: Double?
    var id: String { date }
}
struct VehicleEnergy: Codable, Sendable, Equatable {
    let rankPercent: Double?; let cumulativeRankPercent: Double?; let recentDistanceKm: Double?
    let equivalentFuelLitresPer100Km: Double?; let electricityKwhPer100Km: Double?; let fuelLitresPer100Km: Double?
    let electricityKwh: Double?; let fuelLitres: Double?; let costYuan: Double?; let breakdown: VehicleEnergyBreakdown?
    let recentTrend: [VehicleEnergyTrendPoint]
    let totalDistanceKm: Double?; let cumulativeEquivalentFuelLitresPer100Km: Double?
    let cumulativeElectricityKwhPer100Km: Double?; let cumulativeFuelLitresPer100Km: Double?; let costPerKmYuan: Double?
    let updatedAt: String?
}
struct VehicleDetailSnapshot: Sendable, Equatable { let summary: VehicleSnapshot; let energy: VehicleEnergy }
struct VehicleResource: Codable, Sendable, Identifiable, Equatable { let id: String; let name: String }
protocol VehicleProvider: HomeProvider where Snapshot == VehicleSnapshot {
    func vehicles() async throws -> [VehicleResource]
    func selectVehicle(id: String) async throws
    func detail() async throws -> VehicleDetailSnapshot
}
