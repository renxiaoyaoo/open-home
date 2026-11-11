import Foundation

struct APIClient: Sendable {
    let baseURL: URL
    let credential: @Sendable () throws -> String
    private let session = URLSession.shared

    func get<Response: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        try await request(path, method: "GET", query: query)
    }

    func request<Response: Decodable & Sendable>(_ path: String, method: String, query: [URLQueryItem] = [], headers: [String: String] = [:]) async throws -> Response {
        try await request(path, method: method, query: query, headers: headers, body: nil)
    }

    func send<Response: Decodable & Sendable, Body: Encodable & Sendable>(_ path: String, method: String, body: Body) async throws -> Response {
        try await request(path, method: method, query: [], headers: ["Content-Type": "application/json"], body: try JSONEncoder.openHome.encode(body))
    }

    private func request<Response: Decodable & Sendable>(_ path: String, method: String, query: [URLQueryItem], headers: [String: String], body: Data?) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(try credential())", forHTTPHeaderField: "Authorization")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.message
            if http.statusCode == 401 || http.statusCode == 403 {
                if let message, message.localizedCaseInsensitiveContains("登录") || message.localizedCaseInsensitiveContains("sign") || message.localizedCaseInsensitiveContains("session") {
                    throw APIError.providerAuthenticationRequired(message)
                }
                throw APIError.unauthorized
            }
            throw APIError.server(status: http.statusCode, message: message)
        }
        return try JSONDecoder.openHome.decode(Response.self, from: data)
    }
}

enum APIError: LocalizedError {
    case unauthorized
    case providerAuthenticationRequired(String)
    case invalidResponse
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "OpenHome 连接已失效，请重新连接"
        case .providerAuthenticationRequired(let message): message
        case .invalidResponse: "OpenHome 返回了无法识别的响应"
        case .server(let status, let message): message ?? "OpenHome 请求失败（\(status)）"
        }
    }
}

private struct ErrorEnvelope: Decodable { let message: String? }

private extension JSONDecoder {
    static var openHome: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var openHome: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable { let data: Value }

struct CenterSession: Decodable, Sendable, Equatable {
    let deviceId: String
    let deviceName: String
    let createdAt: Date
    let serverTime: Date
}

extension APIClient {
    func centerSession() async throws -> CenterSession {
        let response: Envelope<CenterSession> = try await get("client/session")
        return response.data
    }

    func revokeCenterSession() async throws {
        let _: Envelope<RevokedCenterSession> = try await request("client/session", method: "DELETE")
    }

    private struct RevokedCenterSession: Decodable, Sendable { let deviceId: String }
}

struct RemoteLiveActivityRegistrar: LiveActivityRegistrar {
    let client: APIClient

    func register(activityID: String, provider: ProviderID, resourceID: String, pushToken: Data) async throws {
        let body = Registration(activityId: activityID, provider: provider.rawValue, resourceId: resourceID, pushToken: pushToken.map { String(format: "%02x", $0) }.joined(), environment: Self.environment)
        let _: Envelope<Acknowledgement> = try await client.send("live-activities", method: "POST", body: body)
    }

    func unregister(activityID: String) async {
        let _: Envelope<Acknowledgement>? = try? await client.send("live-activities", method: "DELETE", body: Removal(activityId: activityID))
    }

    private static var environment: String {
#if DEBUG
        "sandbox"
#else
        "production"
#endif
    }

    private struct Registration: Encodable, Sendable { let activityId: String; let provider: String; let resourceId: String; let pushToken: String; let environment: String }
    private struct Removal: Encodable, Sendable { let activityId: String }
    private struct Acknowledgement: Decodable, Sendable { let activityId: String }
}

struct RemoteGateProvider: GateProvider {
    let client: APIClient
    private struct Selection: Decodable, Sendable { let selected: Bool }
    func resources() async throws -> [GateResource] {
        let response: Envelope<[GateResource]> = try await client.get("doors")
        return response.data
    }
    func setSelected(resourceID: String, selected: Bool) async throws {
        let _: Envelope<Selection> = try await client.send("doors/\(resourceID)", method: "PATCH", body: ["selected": selected])
    }
    func open(resourceID: String, idempotencyKey: String) async throws -> OperationResult {
        try await client.request("doors/\(resourceID)/open", method: "POST", headers: ["Idempotency-Key": idempotencyKey])
    }
    func password(resourceID: String) async throws -> GatePassword {
        let response: Envelope<GatePassword> = try await client.get("doors/\(resourceID)/password")
        return response.data
    }
}

struct RemoteLockProvider: LockProvider {
    let client: APIClient
    func devices() async throws -> [LockDevice] {
        let response: Envelope<[LockDevice]> = try await client.get("lock/devices")
        return response.data
    }
    func detail(deviceID: String) async throws -> LockDetail {
        let response: Envelope<LockDetail> = try await client.get("lock/detail", query: [.init(name: "lockId", value: deviceID)])
        return response.data
    }
    func dynamics(deviceID: String, cursor: String?) async throws -> LockPage<LockEvent> {
        try await eventPage("lock/lock-dynamics", deviceID: deviceID, cursor: cursor)
    }
    func securityLogs(deviceID: String, cursor: String?) async throws -> LockPage<LockEvent> {
        try await eventPage("lock/security-logs", deviceID: deviceID, cursor: cursor)
    }
    func operationLogs(deviceID: String, cursor: String?) async throws -> LockPage<LockEvent> {
        try await eventPage("lock/operation-logs", deviceID: deviceID, cursor: cursor)
    }
    func captures(deviceID: String, cursor: String?) async throws -> LockPage<LockCapture> {
        var query = [URLQueryItem(name: "lockId", value: deviceID)]
        if let cursor { query.append(.init(name: "cursor", value: cursor)) }
        let response: Envelope<LockPage<LockCapture>> = try await client.get("lock/captures", query: query)
        return response.data
    }
    func createTemporaryPassword(deviceID: String) async throws -> LockTemporaryPassword {
        let response: Envelope<LockTemporaryPassword> = try await client.request("lock/temporary-password-create", method: "POST", query: [.init(name: "lockId", value: deviceID)])
        return response.data
    }
    private func eventPage(_ path: String, deviceID: String, cursor: String?) async throws -> LockPage<LockEvent> {
        var query = [URLQueryItem(name: "lockId", value: deviceID)]
        if let cursor { query.append(.init(name: "cursor", value: cursor)) }
        let response: Envelope<LockPage<LockEvent>> = try await client.get(path, query: query)
        return response.data
    }
}

actor RemoteDryerProvider: DryerProvider {
    let client: APIClient
    private var resolved: (device: DryerWire.Device, homeID: String)?

    init(client: APIClient) { self.client = client }

    func snapshot() async throws -> DryerSnapshot {
        let device = try await resolveDryer().device
        let response: Envelope<DryerWire.Status> = try await client.get("dryer/status", query: [.init(name: "deviceId", value: device.applianceCode)])
        let values = response.data.values
        let powered = values["dryer.power"]?.boolValue == true
        let status = values["dryer.workStatus"]?.intValue
        let programID = values["dryer.currentDryingProgramId"]?.intValue
        let remaining = values["dryer.remainingRunningTime"]?.intValue
        let state: DryerSnapshot.State
        if !powered { state = .off }
        else { switch status { case 2: state = .running; case 3, 9: state = .paused; case 4, 8: state = .scheduled; case 5: state = .fault; case 6: state = .finished; default: state = .idle } }
        return DryerSnapshot(deviceID: device.applianceCode, name: device.name ?? "干衣机", state: state, programName: DryerWire.programs[programID ?? -1], programID: programID, remainingMinutes: remaining, expectedFinish: remaining.map { Date().addingTimeInterval(TimeInterval($0 * 60)) })
    }

    func programs() async throws -> [DryerProgram] {
        let value = try await resolveDryer()
        let response: Envelope<DryerWire.Capabilities> = try await client.get("dryer/capabilities", query: [.init(name: "homeId", value: value.homeID), .init(name: "deviceId", value: value.device.applianceCode)])
        return response.data.programs
    }

    func selectProgram(_ program: DryerProgram) async throws {
        let value = try await resolveDryer()
        let _: Envelope<DryerWire.Ignored> = try await client.send("dryer/program", method: "POST", body: DryerWire.ProgramRequest(deviceId: value.device.applianceCode, programId: program.value))
    }

    func configureProgram(_ program: DryerProgram, parameters: [String: Int]) async throws {
        let value = try await resolveDryer()
        let body = DryerWire.ConfiguredProgramRequest(deviceId: value.device.applianceCode, programId: program.value, parameters: parameters)
        let _: Envelope<DryerWire.Ignored> = try await client.send("dryer/program", method: "POST", body: body)
    }

    func setPower(_ powered: Bool) async throws {
        let value = try await resolveDryer()
        let _: Envelope<DryerWire.Ignored> = try await client.send("dryer/power", method: "POST", body: DryerWire.PowerRequest(deviceId: value.device.applianceCode, power: powered))
    }

    func command(_ command: DryerCommand) async throws {
        let value = try await resolveDryer()
        let action: String; let data: [String: Int]
        switch command {
        case .start: action = "startDrying"; data = [:]
        case .pause: action = "pauseDrying"; data = [:]
        case .cancelSchedule: action = "cancelAppointmentDrying"; data = [:]
        case .schedule(let delay): action = "appointmentDrying"; data = ["appointmentTime": delay]
        }
        let _: Envelope<DryerWire.Ignored> = try await client.send("dryer/action", method: "POST", body: DryerWire.ActionRequest(deviceId: value.device.applianceCode, action: action, data: data))
    }

    private func resolveDryer() async throws -> (device: DryerWire.Device, homeID: String) {
        if let resolved { return resolved }
        let homes: Envelope<DryerWire.Homes> = try await client.get("dryer/homes")
        for home in homes.data.homeList ?? [] {
            let response: Envelope<DryerWire.Devices> = try await client.get("dryer/devices", query: [.init(name: "homeId", value: home.homegroupId.description)])
            let rooms = (response.data.homeList ?? []).flatMap { $0.roomList ?? [] }
            let devices = rooms.flatMap { $0.applianceList ?? [] }
            if let found = devices.first(where: { $0.type.description.lowercased() == "0xdc" }) {
                let value = (device: found, homeID: home.homegroupId.description)
                resolved = value
                return value
            }
        }
        throw ProviderError.invalidResponse
    }
}

private enum DryerWire {
    struct Homes: Decodable, Sendable { let homeList: [Home]? }
    struct Home: Decodable, Sendable { let homegroupId: StringOrNumber }
    struct Devices: Decodable, Sendable { let homeList: [DeviceHome]? }
    struct DeviceHome: Decodable, Sendable { let roomList: [Room]? }
    struct Room: Decodable, Sendable { let applianceList: [Device]? }
    struct Device: Decodable, Sendable { let applianceCode: String; let name: String?; let type: StringOrNumber }
    struct Capabilities: Decodable, Sendable { let programs: [DryerProgram] }
    struct ProgramRequest: Encodable, Sendable { let deviceId: String; let programId: Int }
    struct ConfiguredProgramRequest: Encodable, Sendable { let deviceId: String; let programId: Int; let parameters: [String: Int] }
    struct PowerRequest: Encodable, Sendable { let deviceId: String; let power: Bool }
    struct ActionRequest: Encodable, Sendable { let deviceId: String; let action: String; let data: [String: Int] }
    struct Ignored: Decodable, Sendable { init(from decoder: Decoder) throws {} }
    struct Status: Decodable, Sendable {
        let properties: [Property]?
        let data: NestedStatus?
        var values: [String: JSONScalar] { Dictionary(uniqueKeysWithValues: (properties ?? data?.properties ?? []).compactMap { property in property.code.map { ($0, property.value) } }) }
    }
    struct NestedStatus: Decodable, Sendable { let properties: [Property]? }
    struct Property: Decodable, Sendable {
        let code: String?
        let value: JSONScalar
        enum CodingKeys: String, CodingKey { case code, propertyCode, value }
        init(from decoder: Decoder) throws { let container = try decoder.container(keyedBy: CodingKeys.self); code = try container.decodeIfPresent(String.self, forKey: .code) ?? container.decodeIfPresent(String.self, forKey: .propertyCode); value = try container.decode(JSONScalar.self, forKey: .value) }
    }
    static let programs = [2: "混合", 43: "大件烘", 42: "小件烘", 26: "定时烘", 11: "热风暖衣", 39: "空气洗", 17: "快烘", 10: "冷风清新", 83: "除菌除螨", 28: "支架烘", 45: "晒被子", 8: "羊毛", 6: "羽绒服", 0: "棉麻", 14: "婴儿服", 15: "衬衫", 22: "浴巾", 44: "羊毛护理", 13: "内衣", 12: "运动服", 3: "牛仔"]
}

private enum StringOrNumber: Decodable, Sendable, CustomStringConvertible {
    case string(String), number(Int)
    init(from decoder: Decoder) throws { let value = try decoder.singleValueContainer(); if let number = try? value.decode(Int.self) { self = .number(number) } else { self = .string(try value.decode(String.self)) } }
    var description: String { switch self { case .string(let value): value; case .number(let value): String(value) } }
}

private enum JSONScalar: Decodable, Sendable {
    case bool(Bool), number(Double), string(String), null
    init(from decoder: Decoder) throws { let value = try decoder.singleValueContainer(); if value.decodeNil() { self = .null } else if let bool = try? value.decode(Bool.self) { self = .bool(bool) } else if let number = try? value.decode(Double.self) { self = .number(number) } else { self = .string(try value.decode(String.self)) } }
    var boolValue: Bool? { switch self { case .bool(let value): value; case .number(let value): value != 0; case .string(let value): ["1", "true"].contains(value.lowercased()); case .null: nil } }
    var intValue: Int? { switch self { case .number(let value): Int(value); case .string(let value): Int(value); case .bool(let value): value ? 1 : 0; case .null: nil } }
}

actor RemoteVehicleProvider: VehicleProvider {
    let client: APIClient
    private var vehicle: VehicleWire.Vehicle?
    private var initialDetail: VehicleDetailSnapshot?

    init(client: APIClient) { self.client = client }

    func snapshot() async throws -> VehicleSnapshot {
        if vehicle == nil {
            let response: Envelope<VehicleWire.Bootstrap> = try await client.get("auto/bootstrap")
            guard let first = response.data.vehicles.first else { throw ProviderError.invalidResponse }
            vehicle = first
            if let initial = response.data.snapshot {
                let detail = VehicleDetailSnapshot(summary: normalize(initial.summary, fallback: first), energy: initial.energy)
                initialDetail = detail
                return detail.summary
            }
        }
        guard let vehicle else { throw ProviderError.invalidResponse }
        let response: Envelope<VehicleWire.Summary> = try await client.get("auto/status", query: [.init(name: "vehicleId", value: vehicle.id)])
        return normalize(response.data, fallback: vehicle)
    }

    func detail() async throws -> VehicleDetailSnapshot {
        if vehicle == nil { _ = try await snapshot() }
        if let initialDetail { self.initialDetail = nil; return initialDetail }
        guard let vehicle else { throw ProviderError.invalidResponse }
        let response: Envelope<VehicleWire.Snapshot> = try await client.get("auto/summary", query: [.init(name: "vehicleId", value: vehicle.id)])
        return .init(summary: normalize(response.data.summary, fallback: vehicle), energy: response.data.energy)
    }

    private func normalize(_ value: VehicleWire.Summary, fallback: VehicleWire.Vehicle) -> VehicleSnapshot {
        let state: VehicleSnapshot.State
        if value.health?.values.contains("warning") == true { state = .fault }
        else if value.chargingState == "charging" { state = .charging }
        else if value.powerState == "on", (value.speedKph ?? 0) > 0 { state = .driving }
        else if value.powerState == "on" { state = .ready }
        else { state = .parked }
        return .init(vehicleID: value.id, name: value.name.isEmpty ? fallback.name : value.name, state: state, speedKPH: value.speedKph, totalRangeKM: value.estimatedRangeKm, batteryPercent: value.tractionBatteryPercent, fuelPercent: value.fuelPercent, electricRangeKM: value.electricRangeKm, fuelRangeKM: value.fuelRangeKm, odometerKM: value.odometerKm, evMileageKM: value.evMileageKm, hevMileageKM: value.hevMileageKm, cabinTemperatureC: value.cabinTemperatureC, locationName: value.locationName, signalStrength: value.signalStrength, online: value.online, securityState: value.securityState, driveMode: value.driveMode, okIndicator: value.okIndicator, powerOutputKW: value.powerOutputKw, engineCoolantC: value.engineCoolantC, health: value.health, doorsOpen: value.doorsOpen, doorsUnlocked: value.doorsUnlocked, windowsOpen: value.windowsOpen, hoodOpen: value.hoodOpen, trunkOpen: value.trunkOpen, skylightOpen: value.skylightOpen, tirePressureKPA: value.tirePressureKpa, chargingPowerKW: value.chargingPowerKw, remainingChargeMinutes: value.remainingChargeMinutes, updatedAt: value.updatedAt.flatMap(VehicleWire.date))
    }
}

private enum VehicleWire {
    struct Bootstrap: Decodable, Sendable { let vehicles: [Vehicle]; let snapshot: Snapshot? }
    struct Snapshot: Decodable, Sendable { let summary: Summary; let energy: VehicleEnergy }
    struct Vehicle: Decodable, Sendable { let id: String; let name: String }
    struct Summary: Decodable, Sendable {
        let id: String; let name: String; let powerState: String
        let estimatedRangeKm: Double?; let electricRangeKm: Double?; let fuelRangeKm: Double?
        let tractionBatteryPercent: Double?; let fuelPercent: Double?; let chargingState: String?
        let chargingPowerKw: Double?; let remainingChargeMinutes: Int?; let odometerKm: Double?
        let evMileageKm: Double?; let hevMileageKm: Double?; let speedKph: Double?; let cabinTemperatureC: Double?; let locationName: String?
        let signalStrength: Int?; let online: Bool?; let securityState: String?; let driveMode: String?; let okIndicator: Bool?
        let powerOutputKw: Double?; let engineCoolantC: Double?
        let health: [String: String]?; let updatedAt: String?
        let doorsOpen: VehicleCornerState?; let doorsUnlocked: VehicleCornerState?; let windowsOpen: VehicleCornerState?
        let hoodOpen: Bool?; let trunkOpen: Bool?; let skylightOpen: Bool?; let tirePressureKpa: VehicleTirePressure?
    }
    static func date(_ value: String) -> Date? { ISO8601DateFormatter().date(from: value) }
}
