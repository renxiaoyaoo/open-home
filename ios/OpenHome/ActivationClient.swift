import Foundation

struct ActivationClient: Sendable {
    struct Result: Sendable { let baseURL: URL; let deviceID: String; let deviceToken: String }
    private struct Body: Encodable { let code: String; let deviceName: String }
    private struct Response: Decodable { let ok: Bool; let data: DataValue?; let message: String? }
    private struct DataValue: Decodable { let deviceID: String; let deviceToken: String }

    func activate(baseURL: URL, code: String, deviceName: String) async throws -> Result {
        let normalized = code.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "").uppercased()
        guard normalized.range(of: #"^[23456789A-HJ-NP-Z]{8}$"#, options: .regularExpression) != nil else { throw ActivationError.invalidCode }
        guard baseURL.scheme == "https" || (baseURL.scheme == "http" && ["localhost", "127.0.0.1"].contains(baseURL.host)) else { throw ActivationError.invalidAddress }
        var request = URLRequest(url: baseURL.appending(path: "client/activate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(Body(code: normalized, deviceName: deviceName))
        let (responseData, urlResponse) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: responseData)
        guard let http = urlResponse as? HTTPURLResponse, 200..<300 ~= http.statusCode, response.ok, let value = response.data else { throw ActivationError.rejected(response.message) }
        return .init(baseURL: baseURL, deviceID: value.deviceID, deviceToken: value.deviceToken)
    }
}

enum ActivationError: LocalizedError {
    case invalidCode, invalidAddress
    case rejected(String?)
    var errorDescription: String? {
        switch self {
        case .invalidCode: "请输入 8 位激活码"
        case .invalidAddress: "OpenHome 地址无效"
        case .rejected(let message): message ?? "激活码无效或已过期"
        }
    }
}
