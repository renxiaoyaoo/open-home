import Foundation

struct APIClient: Sendable {
    let baseURL: URL
    let credential: @Sendable () throws -> String
    private let session = URLSession.shared

    func get<Response: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        try await request(path, method: "GET", query: query)
    }

    func request<Response: Decodable & Sendable>(_ path: String, method: String, query: [URLQueryItem] = [], headers: [String: String] = [:]) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try credential())", forHTTPHeaderField: "Authorization")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.userAuthenticationRequired) }
        return try JSONDecoder.openHome.decode(Response.self, from: data)
    }
}

private extension JSONDecoder {
    static var openHome: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable { let data: Value }

struct RemoteGateProvider: GateProvider {
    let client: APIClient
    func resources() async throws -> [GateResource] {
        let response: Envelope<[GateResource]> = try await client.get("doors")
        return response.data
    }
    func open(resourceID: String, idempotencyKey: String) async throws -> OperationResult {
        try await client.request("doors/\(resourceID)/open", method: "POST", headers: ["Idempotency-Key": idempotencyKey])
    }
    func password(resourceID: String) async throws -> GatePassword {
        let response: Envelope<GatePassword> = try await client.get("doors/\(resourceID)/password")
        return response.data
    }
}

struct RemoteDryerProvider: HomeProvider {
    let client: APIClient
    func snapshot() async throws -> DryerSnapshot {
        let response: Envelope<DryerSnapshot> = try await client.get("dryer/status")
        return response.data
    }
}

struct RemoteVehicleProvider: HomeProvider {
    let client: APIClient
    func snapshot() async throws -> VehicleSnapshot {
        let response: Envelope<VehicleSnapshot> = try await client.get("auto/status")
        return response.data
    }
}
