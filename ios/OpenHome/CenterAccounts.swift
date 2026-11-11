import Observation
import SwiftUI

struct CenterAccount: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
}

struct CenterAccountClient: Sendable {
    private let client: APIClient
    init(client: APIClient) { self.client = client }

    func accounts(for provider: ProviderID) async throws -> [CenterAccount] {
        switch provider {
        case .gate:
            let response: Envelope<[GateAccount]> = try await client.get("accounts")
            return response.data.map { .init(id: $0.id, displayName: $0.username) }
        case .living:
            return [try await profile(path: "dryer/profile")]
        case .lock:
            return [try await profile(path: "lock/profile")]
        case .auto:
            return [try await profile(path: "auto/profile")]
        }
    }

    func requestCode(provider: ProviderID, mobile: String, accountID: String?) async throws {
        let response: Acknowledgement
        switch provider {
        case .gate:
            guard let accountID else { throw AccountError.missingAccount }
            response = try await client.send("accounts/\(accountID)/sms", method: "POST", body: ["mobile": mobile])
        case .living:
            response = try await client.send("dryer/sms", method: "POST", body: ["mobile": mobile])
        case .lock, .auto:
            throw AccountError.verificationCodeUnsupported
        }
        guard response.ok else { throw AccountError.rejected(response.message) }
    }

    func signIn(provider: ProviderID, accountID: String?, mobile: String, secret: String) async throws {
        let response: Acknowledgement
        switch provider {
        case .gate:
            guard let accountID else { throw AccountError.missingAccount }
            response = try await client.send("accounts/\(accountID)/login", method: "POST", body: ["mobile": mobile, "smsCode": secret])
        case .living:
            response = try await client.send("dryer/login", method: "POST", body: ["mobile": mobile, "code": secret])
        case .lock:
            response = try await client.send("lock/login", method: "POST", body: ["phone": mobile, "password": secret])
        case .auto:
            response = try await client.send("auto/login", method: "POST", body: ["phone": mobile, "password": secret])
        }
        guard response.ok else { throw AccountError.rejected(response.message) }
    }

    func signOut(provider: ProviderID, accountID: String) async throws {
        let response: Acknowledgement
        switch provider {
        case .gate:
            response = try await client.request("accounts/\(accountID)", method: "DELETE")
        case .living:
            response = try await client.send("dryer/logout", method: "POST", body: ["accountId": accountID])
        case .lock:
            response = try await client.send("lock/logout", method: "POST", body: ["accountId": accountID])
        case .auto:
            response = try await client.request("auto/logout", method: "POST", query: [.init(name: "accountId", value: accountID)])
        }
        guard response.ok else { throw AccountError.rejected(response.message) }
    }

    private func profile(path: String) async throws -> CenterAccount {
        let response: Envelope<Profile> = try await client.get(path)
        return .init(id: response.data.accountId, displayName: response.data.displayName ?? "已连接账号")
    }

    private struct GateAccount: Decodable, Sendable { let id: String; let username: String }
    private struct Profile: Decodable, Sendable { let accountId: String; let displayName: String? }
    private struct Acknowledgement: Decodable, Sendable { let ok: Bool; let message: String? }
}

private enum AccountError: LocalizedError {
    case missingAccount, verificationCodeUnsupported, rejected(String?)
    var errorDescription: String? {
        switch self {
        case .missingAccount: "账号标识无效"
        case .verificationCodeUnsupported: "该模块使用密码登录"
        case .rejected(let message): message ?? "账号操作失败"
        }
    }
}

@MainActor
@Observable
private final class CenterAccountModel {
    var accounts: [ProviderID: [CenterAccount]] = [:]
    var isLoading = false
    var isBusy = false
    var message: String?
    private let client: CenterAccountClient

    init(client: CenterAccountClient) { self.client = client }

    func load(_ provider: ProviderID) async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do { accounts[provider] = try await client.accounts(for: provider); message = nil }
        catch APIError.unauthorized { accounts[provider] = []; message = nil }
        catch APIError.providerAuthenticationRequired { accounts[provider] = []; message = nil }
        catch { accounts[provider] = []; message = error.localizedDescription }
    }

    func requestCode(provider: ProviderID, mobile: String, accountID: String?) async -> Bool {
        await perform { try await client.requestCode(provider: provider, mobile: mobile, accountID: accountID) }
    }

    func signIn(provider: ProviderID, accountID: String?, mobile: String, secret: String) async -> Bool {
        let succeeded = await perform { try await client.signIn(provider: provider, accountID: accountID, mobile: mobile, secret: secret) }
        if succeeded { await load(provider) }
        return succeeded
    }

    func signOut(provider: ProviderID, accountID: String) async {
        if await perform({ try await client.signOut(provider: provider, accountID: accountID) }) { await load(provider) }
    }

    private func perform(_ operation: () async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; message = nil; defer { isBusy = false }
        do { try await operation(); return true }
        catch { message = error.localizedDescription; return false }
    }
}

struct CenterAccountManagementView: View {
    @State private var model: CenterAccountModel
    @State private var provider: ProviderID
    @State private var mobile = ""
    @State private var secret = ""
    @State private var pendingGateID: String?
    @State private var showingLogin = false
    @State private var confirmingLogout: CenterAccount?
    @Environment(\.dismiss) private var dismiss
    private let providers: [ProviderID]

    init(client: CenterAccountClient, providers: Set<ProviderID>) {
        let ordered = ProviderID.allCases.filter(providers.contains)
        self.providers = ordered
        _provider = State(initialValue: ordered.first ?? .gate)
        _model = State(initialValue: CenterAccountModel(client: client))
    }

    var body: some View {
        NavigationStack {
            Form {
                if providers.count > 1 {
                    Picker("模块", selection: $provider) {
                        ForEach(providers, id: \.self) { Text(moduleName($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                accountSection
                if shouldShowLogin { loginSection }
                if let message = model.message { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle("账号管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task(id: provider) { resetLogin(); await model.load(provider) }
            .refreshable { await model.load(provider) }
            .confirmationDialog("退出此账号？", isPresented: Binding(get: { confirmingLogout != nil }, set: { if !$0 { confirmingLogout = nil } }), titleVisibility: .visible) {
                Button("确认退出", role: .destructive) { if let account = confirmingLogout { Task { await model.signOut(provider: provider, accountID: account.id); confirmingLogout = nil } } }
                Button("取消", role: .cancel) { confirmingLogout = nil }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private var accountSection: some View {
        Section("已连接") {
            if model.isLoading { HStack { Spacer(); ProgressView(); Spacer() } }
            else if currentAccounts.isEmpty { Text("尚未登录").foregroundStyle(.secondary) }
            else {
                ForEach(currentAccounts) { account in
                    HStack {
                        Label(account.displayName, systemImage: moduleSymbol(provider))
                        Spacer()
                        Button("退出", role: .destructive) { confirmingLogout = account }.disabled(model.isBusy)
                    }
                }
            }
            if provider == .gate && !showingLogin { Button("添加账号", systemImage: "plus") { showingLogin = true } }
        }
    }

    @ViewBuilder private var loginSection: some View {
        Section(provider == .gate && !currentAccounts.isEmpty ? "添加账号" : "登录") {
            TextField("手机号", text: $mobile).keyboardType(.phonePad).textContentType(.telephoneNumber)
            if usesCode {
                HStack {
                    TextField("6 位验证码", text: $secret).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    Button("获取验证码") { Task { await requestCode() } }.disabled(model.isBusy || mobile.count != 11)
                }
            } else {
                SecureField("密码", text: $secret).textContentType(.password)
            }
            Button(model.isBusy ? "处理中…" : "登录") { Task { await signIn() } }
                .frame(maxWidth: .infinity)
                .disabled(model.isBusy || mobile.count != 11 || secret.isEmpty)
        }
    }

    private var currentAccounts: [CenterAccount] { model.accounts[provider] ?? [] }
    private var usesCode: Bool { provider == .gate || provider == .living }
    private var shouldShowLogin: Bool { provider == .gate ? showingLogin || currentAccounts.isEmpty : currentAccounts.isEmpty }

    private func requestCode() async {
        if provider == .gate, pendingGateID == nil { pendingGateID = "og-\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12))" }
        _ = await model.requestCode(provider: provider, mobile: mobile, accountID: pendingGateID)
    }

    private func signIn() async {
        if provider == .gate, pendingGateID == nil { pendingGateID = "og-\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12))" }
        if await model.signIn(provider: provider, accountID: pendingGateID, mobile: mobile, secret: secret) { resetLogin() }
    }

    private func resetLogin() { mobile = ""; secret = ""; pendingGateID = nil; showingLogin = false }
    private func moduleName(_ provider: ProviderID) -> String { switch provider { case .gate: "门禁"; case .living: "智能家电"; case .lock: "智能门锁"; case .auto: "车辆" } }
    private func moduleSymbol(_ provider: ProviderID) -> String { switch provider { case .gate: "door.left.hand.open"; case .living: "washer"; case .lock: "lock.shield"; case .auto: "car.side" } }
}
