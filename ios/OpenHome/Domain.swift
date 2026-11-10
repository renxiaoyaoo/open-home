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
    var id: String { "\(group)|\(value)|\(name)" }
}

enum DryerCommand: Sendable { case start, pause, cancelSchedule, schedule(delayMinutes: Int) }

protocol DryerProvider: HomeProvider where Snapshot == DryerSnapshot {
    func programs() async throws -> [DryerProgram]
    func selectProgram(_ program: DryerProgram) async throws
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
struct LockPage<Item: Codable & Sendable>: Codable, Sendable { let items: [Item]; let nextCursor: String? }
struct LockTemporaryPassword: Codable, Sendable, Equatable { let password: String; let expiresAt: Date }

protocol LockProvider: Sendable {
    func devices() async throws -> [LockDevice]
    func detail(deviceID: String) async throws -> LockDetail
    func dynamics(deviceID: String, cursor: String?) async throws -> LockPage<LockEvent>
    func createTemporaryPassword(deviceID: String) async throws -> LockTemporaryPassword
}

struct DryerSnapshot: Codable, Sendable, Equatable {
    let deviceID: String
    let name: String
    let state: State
    let programName: String?
    let programID: Int?
    let remainingMinutes: Int?
    let expectedFinish: Date?

    enum State: String, Codable, Sendable { case off, idle, running, paused, scheduled, finished, fault }
}

struct VehicleSnapshot: Codable, Sendable, Equatable {
    let vehicleID: String
    let name: String
    let state: State
    let speedKPH: Double?
    let totalRangeKM: Double?
    let batteryPercent: Double?
    let fuelPercent: Double?
    let electricRangeKM: Double?
    let fuelRangeKM: Double?
    let odometerKM: Double?
    let cabinTemperatureC: Double?
    let locationName: String?
    let chargingPowerKW: Double?
    let remainingChargeMinutes: Int?
    let updatedAt: Date?

    enum State: String, Codable, Sendable { case parked, ready, driving, charging, fault }
}
