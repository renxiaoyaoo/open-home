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

protocol HomeProvider<Snapshot>: Sendable {
    associatedtype Snapshot: Sendable
    func snapshot() async throws -> Snapshot
}

struct DryerSnapshot: Codable, Sendable, Equatable {
    let deviceID: String
    let name: String
    let state: State
    let programName: String?
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

    enum State: String, Codable, Sendable { case parked, ready, driving, charging, fault }
}
