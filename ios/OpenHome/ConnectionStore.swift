import Foundation

struct ConnectionStore {
    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard
    private let configurationKey = "openhome.connection"
    private let tokenAccount = "center.device-token"

    func saveCenter(_ result: ActivationClient.Result) throws -> ConnectionConfiguration {
        try keychain.save(Data(result.deviceToken.utf8), account: tokenAccount)
        let configuration = ConnectionConfiguration(mode: .center, centerURL: result.baseURL, deviceCredentialID: result.deviceID, enabledProviders: Set(ProviderID.allCases))
        defaults.set(try JSONEncoder().encode(configuration), forKey: configurationKey)
        return configuration
    }

    func load() -> ConnectionConfiguration? {
        guard let data = defaults.data(forKey: configurationKey) else { return nil }
        return try? JSONDecoder().decode(ConnectionConfiguration.self, from: data)
    }

    func centerToken() throws -> String {
        guard let data = try keychain.read(account: tokenAccount), let value = String(data: data, encoding: .utf8) else { throw URLError(.userAuthenticationRequired) }
        return value
    }
}
