import Foundation

struct ActivationClient: Sendable {
    struct Result: Sendable { let baseURL: URL; let deviceID: String; let deviceToken: String }
    private struct Payload: Decodable { let baseURL: URL; let code: String }
    private struct Body: Encodable { let code: String; let deviceName: String }
    private struct Response: Decodable { let ok: Bool; let data: DataValue?; let message: String? }
    private struct DataValue: Decodable { let deviceID: String; let deviceToken: String }

    func activate(package: String, deviceName: String) async throws -> Result {
        guard package.hasPrefix("oh1."), let encoded = package.split(separator: ".", maxSplits: 1).last,
              let data = Data(base64URLEncoded: String(encoded)) else { throw ActivationError.invalidCode }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        var request = URLRequest(url: payload.baseURL.appending(path: "client/activate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(Body(code: payload.code, deviceName: deviceName))
        let (responseData, urlResponse) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: responseData)
        guard let http = urlResponse as? HTTPURLResponse, 200..<300 ~= http.statusCode, response.ok, let value = response.data else { throw ActivationError.rejected(response.message) }
        return .init(baseURL: payload.baseURL, deviceID: value.deviceID, deviceToken: value.deviceToken)
    }
}

enum ActivationError: LocalizedError {
    case invalidCode
    case rejected(String?)
    var errorDescription: String? {
        switch self {
        case .invalidCode: "激活码格式无效"
        case .rejected(let message): message ?? "激活码无效或已过期"
        }
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
