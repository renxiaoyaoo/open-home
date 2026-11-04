import Foundation

struct APIClient: Sendable {
    let baseURL: URL
    let credential: @Sendable () throws -> String
    private let session = URLSession.shared

    func get<Response: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try credential())", forHTTPHeaderField: "Authorization")
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

private struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable { let data: Value }

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
