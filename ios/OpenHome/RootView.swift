import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingDirectLogout = false
    @State private var confirmingDisconnect = false
    @State private var showingModules = false
    @State private var showingAccounts = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.connection == nil {
                    ConnectionSetupView()
                } else {
                    Group {
                        if model.enabledModules.isEmpty {
                            ContentUnavailableView {
                                Label("尚未添加模块", systemImage: "square.grid.2x2")
                            } actions: {
                                Button("添加模块") { showingModules = true }
                                    .buttonStyle(.borderedProminent)
                            }
                        } else {
                            TabView(selection: $model.selectedModule) {
                                ForEach(model.enabledModules) { module in
                                    connectedContent(module)
                                        .tabItem { Label(module.subtitle, systemImage: module.symbol) }
                                        .tag(module)
                                }
                            }
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            if model.connection?.mode == .center {
                                Button("账号管理", systemImage: "person.crop.circle") { showingAccounts = true }
                            }
                            connectionMenu
                        }
                    }
                }
            }
            .background(Color.openHomeBackground)
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.openHomeAccent)
        .confirmationDialog("退出当前账号？", isPresented: $confirmingDirectLogout, titleVisibility: .visible) {
            Button("确认退出", role: .destructive) { try? model.signOutSelectedDirectProvider() }
            Button("取消", role: .cancel) {}
        } message: { Text(model.selectedModule.rawValue) }
        .confirmationDialog("断开 OpenHome？", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("断开连接", role: .destructive) { Task { await model.disconnectCenter() } }
            Button("取消", role: .cancel) {}
        } message: { Text("此设备的连接凭据将被移除") }
        .task(id: model.connection?.deviceCredentialID) { await model.validateCenter() }
        .sheet(isPresented: $showingModules) { ModuleManagementView() }
        .sheet(isPresented: $showingAccounts) {
            if let connection = model.connection, connection.mode == .center, let baseURL = connection.centerURL {
                CenterAccountManagementView(client: CenterAccountClient(client: APIClient(baseURL: baseURL, credential: { try ConnectionStore().centerToken() })), providers: connection.enabledProviders)
            }
        }
    }

    @ViewBuilder private func connectedContent(_ module: AppModel.Module) -> some View {
        if model.connection?.enabledProviders.contains(module.providerID) != true {
            ModuleUnavailableView(module: module, message: "此模块未启用")
        } else if let factory = model.providerFactory() {
            ProviderModuleView(module: module, factory: factory, directRegistry: model.connection?.mode == .direct ? model.directProviders : nil)
                .id("\(module.id)-\(model.sessionRevision)")
        } else {
            ModuleUnavailableView(module: module, message: "连接配置不可用")
        }
    }

    private var connectionMenu: some View {
        Menu {
                if case .connected(let session) = model.centerState {
                    Text(session.deviceName)
                } else if case .unavailable = model.centerState {
                    Button("重新检查连接", systemImage: "arrow.clockwise") { Task { await model.validateCenter() } }
                } else if model.centerState == .revoked {
                    Text("连接已失效")
                }
                if model.connection?.mode == .direct {
                    Button("退出当前账号", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmingDirectLogout = true }
                }
                Button("管理模块", systemImage: "square.grid.2x2") { showingModules = true }
                Button("切换连接方式", systemImage: "arrow.triangle.2.circlepath") {
                    if model.connection?.mode == .center { confirmingDisconnect = true } else { model.disconnect() }
                }
        } label: { Image(systemName: "ellipsis.circle") }
        .accessibilityLabel("连接管理")
    }
}

private struct ModuleManagementView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.availableModules) { module in
                        Toggle(isOn: Binding(
                            get: { model.connection?.enabledProviders.contains(module.providerID) == true },
                            set: { enabled in
                                do { try model.setModule(module, enabled: enabled); errorMessage = nil }
                                catch { errorMessage = error.localizedDescription }
                            }
                        )) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(module.rawValue)
                                    Text(module.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: module.symbol).foregroundStyle(Color.openHomeAccent)
                            }
                        }
                    }
                } footer: {
                    Text(model.connection?.mode == .center ? "模块使用同一 OpenHome 中心连接。" : "仅显示此设备已安装的直连 Provider。")
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("模块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ConnectionSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: ConnectionMode = .center
    @State private var activationCode = ""
    @State private var isActivating = false
    @State private var errorMessage: String?
    @State private var directProviders: Set<ProviderID> = []

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
                        if model.directProviders.installed.isEmpty {
                            ContentUnavailableView("没有可用的直连模块", systemImage: "shippingbox", description: Text("此构建未安装直连 Provider"))
                        } else {
                            Text("选择要在本机使用的模块").font(.subheadline).foregroundStyle(.secondary)
                            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
                                ForEach(AppModel.Module.allCases.filter { model.directProviders.installed.contains($0.providerID) }) { module in
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
                }
                .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 18))
            }.padding(14).frame(maxWidth: 520)
        }
        .onAppear { directProviders = model.directProviders.installed }
    }

    @MainActor
    private func activate() async {
        isActivating = true; errorMessage = nil
        defer { isActivating = false }
        do {
            let result = try await ActivationClient().activate(package: activationCode.trimmingCharacters(in: .whitespacesAndNewlines), deviceName: "iPhone")
            model.connection = try ConnectionStore().saveCenter(result)
            await model.validateCenter()
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
            resolved { LockView(provider: try factory.lockProvider()) }
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
