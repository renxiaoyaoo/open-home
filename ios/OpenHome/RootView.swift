import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                moduleSwitcher
                Group {
                    if model.connection == nil { ConnectionSetupView() }
                    else { connectedContent }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.openHomeBackground)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.openHomeAccent)
    }

    @ViewBuilder private var connectedContent: some View {
        if model.connection?.enabledProviders.contains(model.selectedModule.providerID) != true {
            ModuleUnavailableView(module: model.selectedModule, message: "此模块未启用")
        } else if let factory = model.providerFactory() {
            ProviderModuleView(module: model.selectedModule, factory: factory, directRegistry: model.connection?.mode == .direct ? model.directProviders : nil)
        } else {
            ModuleUnavailableView(module: model.selectedModule, message: "连接配置不可用")
        }
    }

    private var moduleSwitcher: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                ForEach(AppModel.Module.allCases) { module in
                    let selected = model.selectedModule == module
                    Button { model.selectedModule = module } label: {
                        HStack(spacing: 7) {
                            Image(systemName: module.symbol).foregroundStyle(selected ? .white : .primary).frame(width: 24, height: 24).background(.white.opacity(selected ? 0.18 : 1), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(module.rawValue).font(.system(size: 12, weight: .semibold)).foregroundStyle(selected ? .white : .primary)
                                Text(module.subtitle).font(.system(size: 9)).foregroundStyle(selected ? .white.opacity(0.78) : .secondary)
                            }
                        }
                        .padding(.horizontal, 10).frame(height: 48)
                        .background(selected ? Color.openHomeAccent : .white, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
                }.padding(.leading, 14)
            }
            .scrollIndicators(.hidden)
            Menu {
                Button("切换连接方式", systemImage: "arrow.triangle.2.circlepath") { model.disconnect() }
            } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 40, height: 48).background(.white, in: RoundedRectangle(cornerRadius: 13)) }
            .buttonStyle(.plain).padding(.trailing, 14)
        }
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }
}

private struct ConnectionSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: ConnectionMode = .center
    @State private var activationCode = ""
    @State private var isActivating = false
    @State private var errorMessage: String?
    @State private var directProviders = Set(ProviderID.allCases)

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("连接方式", selection: $mode) {
                    Text("连接 OpenHome").tag(ConnectionMode.center)
                    Text("仅在此设备使用").tag(ConnectionMode.direct)
                }.pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: mode == .center ? "house.and.flag" : "iphone.gen3").font(.title2).foregroundStyle(Color.openHomeAccent)
                    Text(mode == .center ? "连接自己的 OpenHome" : "直接连接设备服务").font(.title2.bold())
                    if mode == .center {
                        TextField("激活码", text: $activationCode).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                        Button(isActivating ? "正在连接…" : "继续") { Task { await activate() } }.buttonStyle(OpenHomePrimaryButton()).disabled(activationCode.isEmpty || isActivating)
                        if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                    } else {
                        Text("选择要在本机使用的模块").font(.subheadline).foregroundStyle(.secondary)
                        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
                            ForEach(AppModel.Module.allCases) { module in
                                let selected = directProviders.contains(module.providerID)
                                Button { if selected { directProviders.remove(module.providerID) } else { directProviders.insert(module.providerID) } } label: {
                                    HStack { Image(systemName: module.symbol); Text(module.rawValue).font(.caption.bold()); Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "circle") }
                                        .padding(12).foregroundStyle(selected ? Color.openHomeAccent : .secondary).background(selected ? Color.openHomeAccent.opacity(0.10) : Color.openHomeBackground, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain)
                            }
                        }
                        Button("继续") { do { model.connection = try ConnectionStore().saveDirect(providers: directProviders) } catch { errorMessage = error.localizedDescription } }.buttonStyle(OpenHomePrimaryButton()).disabled(directProviders.isEmpty)
                    }
                }
                .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 18))
            }.padding(14).frame(maxWidth: 520)
        }
    }

    @MainActor
    private func activate() async {
        isActivating = true; errorMessage = nil
        defer { isActivating = false }
        do {
            let result = try await ActivationClient().activate(package: activationCode.trimmingCharacters(in: .whitespacesAndNewlines), deviceName: "iPhone")
            model.connection = try ConnectionStore().saveCenter(result)
            activationCode = ""
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ProviderModuleView: View {
    let module: AppModel.Module
    let factory: any ProviderFactory
    let directRegistry: DirectProviderRegistry?
    @State private var authenticationRevision = 0

    @ViewBuilder
    var body: some View {
        switch module {
        case .gate:
            resolved { GateView(provider: try factory.gateProvider()) }
        case .living:
            resolved { DryerView(provider: try factory.dryerProvider(), registrar: factory.liveActivityRegistrar()) }
        case .auto:
            resolved { VehicleView(provider: try factory.vehicleProvider(), registrar: factory.liveActivityRegistrar()) }
        case .lock:
            ModuleUnavailableView(module: module, message: "Provider 尚未接入")
        }
    }

    private func resolved<Content: View>(content: () throws -> Content) -> AnyView {
        do { return AnyView(try content()) }
        catch ProviderError.authenticationRequired {
            guard let authenticator = try? directRegistry?.authenticator(module.providerID) else {
                return AnyView(ModuleUnavailableView(module: module, message: "登录组件不可用"))
            }
            return AnyView(DirectLoginView(module: module, authenticator: authenticator) { authenticationRevision += 1 }.id(authenticationRevision))
        } catch {
            return AnyView(ModuleUnavailableView(module: module, message: error.localizedDescription))
        }
    }
}

private struct DirectLoginView: View {
    let module: AppModel.Module
    let authenticator: any DirectProviderAuthenticator
    let onAuthenticated: () -> Void
    @State private var account = ""
    @State private var secret = ""
    @State private var method: DirectLoginMethod
    @State private var isBusy = false
    @State private var message: String?

    init(module: AppModel.Module, authenticator: any DirectProviderAuthenticator, onAuthenticated: @escaping () -> Void) {
        self.module = module
        self.authenticator = authenticator
        self.onAuthenticated = onAuthenticated
        _method = State(initialValue: authenticator.configuration.methods.first ?? .password)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: module.symbol).font(.title2).foregroundStyle(Color.openHomeAccent)
                Text("登录 \(module.rawValue)").font(.title2.bold())
                if authenticator.configuration.methods.count > 1 {
                    Picker("登录方式", selection: $method) {
                        ForEach(authenticator.configuration.methods) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
                TextField(authenticator.configuration.accountLabel, text: $account)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    SecureField(method == .password ? "密码" : "验证码", text: $secret).textContentType(method == .password ? .password : .oneTimeCode).textFieldStyle(.roundedBorder)
                    if method == .verificationCode {
                        Button("获取验证码") { Task { await requestCode() } }.buttonStyle(.bordered).disabled(account.isEmpty || isBusy)
                    }
                }
                Button(isBusy ? "正在登录…" : "登录") { Task { await signIn() } }.buttonStyle(OpenHomePrimaryButton()).disabled(account.isEmpty || secret.isEmpty || isBusy)
                if let message { Text(message).font(.caption).foregroundStyle(.red) }
            }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 18)).padding(14).frame(maxWidth: 520)
        }
    }

    @MainActor private func requestCode() async {
        isBusy = true; message = nil
        defer { isBusy = false }
        do { try await authenticator.requestVerificationCode(account: account) }
        catch { message = error.localizedDescription }
    }

    @MainActor private func signIn() async {
        isBusy = true; message = nil
        defer { isBusy = false }
        do {
            let session = try await authenticator.signIn(account: account, secret: secret, method: method)
            try DirectSessionStore().save(session, provider: module.providerID)
            secret = ""
            onAuthenticated()
        }
        catch { message = error.localizedDescription }
    }
}

private struct ModuleUnavailableView: View {
    let module: AppModel.Module
    let message: String
    var body: some View {
        ContentUnavailableView(message, systemImage: module.symbol)
    }
}

private struct OpenHomePrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fontWeight(.semibold).frame(maxWidth: .infinity).frame(height: 46).foregroundStyle(.white).background(Color.openHomeAccent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension Color {
    static let openHomeBackground = Color(red: 0.961, green: 0.957, blue: 0.937)
    static let openHomeAccent = Color(red: 0.286, green: 0.420, blue: 0.443)
}
