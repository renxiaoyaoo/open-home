import SwiftUI
import UIKit
import VisionKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingDirectLogout = false
    @State private var confirmingDisconnect = false
    @State private var showingModules = false
    @State private var showingAccounts = false
    @State private var activationError: String?

    var body: some View {
        @Bindable var model = model
        Group {
            if model.connection == nil {
                NavigationStack { ConnectionSetupView() }
            } else if model.enabledModules.isEmpty {
                NavigationStack {
                    List {
                        Section {
                            Button("添加模块", systemImage: "plus") { showingModules = true }
                        } footer: {
                            Text("添加后会出现在底部。")
                        }
                    }
                    .navigationTitle("OpenHome")
                    .toolbar { moduleToolbar }
                }
            } else {
                TabView(selection: $model.selectedModule) {
                    ForEach(model.enabledModules) { module in
                        NavigationStack {
                            connectedContent(module)
                                .navigationTitle("")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar { moduleToolbar }
                        }
                        .tabItem { Label(module.tabTitle, systemImage: module.symbol) }
                        .tag(module)
                    }
                }
            }
        }
        .confirmationDialog("退出当前账号？", isPresented: $confirmingDirectLogout, titleVisibility: .visible) {
            Button("确认退出", role: .destructive) { try? model.signOutSelectedDirectProvider() }
            Button("取消", role: .cancel) {}
        } message: { Text(model.selectedModule.rawValue) }
        .confirmationDialog("断开连接？", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("断开连接", role: .destructive) {
                if model.connection?.mode == .center { Task { await model.disconnectCenter() } }
                else { model.disconnect() }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("此设备会退出 OpenHome，需要重新连接才能继续使用。") }
        .task(id: model.connection?.deviceCredentialID) { await model.validateCenter(deviceName: UIDevice.current.name) }
        .onOpenURL { url in Task { await activate(url) } }
        .alert("无法连接 OpenHome", isPresented: Binding(get: { activationError != nil }, set: { if !$0 { activationError = nil } })) {
            Button("好") { activationError = nil }
        } message: {
            Text(activationError ?? "激活失败")
        }
        .sheet(isPresented: $showingModules) { ModuleManagementView() }
        .sheet(isPresented: $showingAccounts) {
            if let connection = model.connection, connection.mode == .center, let baseURL = connection.centerURL {
                CenterAccountManagementView(client: CenterAccountClient(client: APIClient(baseURL: baseURL, credential: { try ConnectionStore().centerToken() })), providers: connection.enabledProviders)
            }
        }
    }

    @MainActor
    private func activate(_ url: URL) async {
        guard let values = URLComponents(url: url, resolvingAgainstBaseURL: false),
              url.scheme == "openhome", url.host == "activate",
              let address = values.queryItems?.first(where: { $0.name == "server" })?.value,
              let code = values.queryItems?.first(where: { $0.name == "code" })?.value,
              let baseURL = URL(string: address) else {
            activationError = "无法识别激活链接"
            return
        }
        do {
            let result = try await ActivationClient().activate(baseURL: baseURL, code: code, deviceName: UIDevice.current.name)
            model.connection = try ConnectionStore().saveCenter(result)
            await model.validateCenter()
            if case .connected = model.centerState { activationError = nil }
            else { activationError = "连接验证失败，请重试" }
        } catch {
            activationError = error.localizedDescription
        }
    }

    @ViewBuilder private func connectedContent(_ module: AppModel.Module) -> some View {
        if model.connection?.enabledProviders.contains(module.providerID) != true {
            ModuleUnavailableView(module: module, message: "此模块未启用")
        } else if let factory = model.providerFactory() {
            ProviderModuleView(module: module, factory: factory, directRegistry: model.connection?.mode == .direct ? model.directProviders : nil)
                .id("\(module.id)-\(model.sessionRevision)")
                .environment(model)
        } else {
            ModuleUnavailableView(module: module, message: "连接配置不可用")
        }
    }

    @ToolbarContentBuilder private var moduleToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.connection?.mode == .center {
                Button("账号管理", systemImage: "person.crop.circle") { showingAccounts = true }
            }
            connectionMenu
        }
    }

    private var connectionMenu: some View {
        Menu {
                if case .connected(let session) = model.centerState {
                    Label(session.deviceName, systemImage: "iphone")
                    Label("设备代号 \(String(session.deviceId.suffix(4)).uppercased())", systemImage: "number")
                } else if case .unavailable = model.centerState {
                    Button("重新检查连接", systemImage: "arrow.clockwise") { Task { await model.validateCenter() } }
                } else if model.centerState == .revoked {
                    Text("连接已失效")
                }
                if model.connection?.mode == .direct {
                    Button("退出当前账号", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmingDirectLogout = true }
                }
                Button("管理模块", systemImage: "square.grid.2x2") { showingModules = true }
                Button("断开连接", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmingDisconnect = true }
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
    @AppStorage("openhome.last-center-url") private var centerAddress = ""
    @State private var activationCode = ""
    @State private var isActivating = false
    @State private var errorMessage: String?
    @State private var directProviders: Set<ProviderID> = []
    @State private var showingScanner = false
    @State private var showingManualActivation = false

    var body: some View {
        Form {
            Section {
                Picker("连接方式", selection: $mode) {
                    Text("连接 OpenHome").tag(ConnectionMode.center)
                    Text("仅在此设备使用").tag(ConnectionMode.direct)
                }.pickerStyle(.segmented)
            }

            if mode == .center {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "house.and.flag.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.openHomeAccent)
                        Text("连接 OpenHome")
                            .font(.title2.bold())
                        Text("扫描管理页生成的二维码，或直接在 iPhone 上打开连接链接。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section {
                    Button {
                        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable { showingScanner = true }
                        else { errorMessage = "此设备当前无法使用相机扫描" }
                    } label: {
                        Label("扫描二维码", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    DisclosureGroup("手动输入", isExpanded: $showingManualActivation) {
                        VStack(spacing: 12) {
                            TextField("OpenHome 地址（管理页复制）", text: $centerAddress)
                                .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            TextField("激活码", text: $activationCode)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                .font(.system(.title3, design: .monospaced).weight(.semibold))
                                .onChange(of: activationCode) { _, value in activationCode = formattedActivationCode(value) }
                            Button(isActivating ? "正在连接…" : "连接") { Task { await activate() } }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity)
                                .disabled(activationCode.count != 9 || isActivating)
                        }
                        .padding(.top, 8)
                    }
                } footer: {
                    Text("管理页会同时显示 OpenHome 地址和激活码。")
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                }
            } else {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "iphone.gen3").font(.system(size: 36)).foregroundStyle(Color.openHomeAccent)
                        Text("仅在此设备使用").font(.title2.bold())
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section {
                    if model.directProviders.installed.isEmpty {
                        ContentUnavailableView("没有可用的直连模块", systemImage: "shippingbox", description: Text("此构建未安装直连 Provider"))
                    } else {
                        ForEach(AppModel.Module.allCases.filter { model.directProviders.installed.contains($0.providerID) }) { module in
                                let selected = directProviders.contains(module.providerID)
                            Button { if selected { directProviders.remove(module.providerID) } else { directProviders.insert(module.providerID) } } label: {
                                Label { HStack { Text(module.rawValue); Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "circle") } } icon: { Image(systemName: module.symbol) }
                            }.buttonStyle(.plain).foregroundStyle(selected ? Color.openHomeAccent : .secondary)
                        }
                    }
                }
                Section {
                    Button("继续") { do { model.connection = try ConnectionStore().saveDirect(providers: directProviders) } catch { errorMessage = error.localizedDescription } }
                        .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(directProviders.isEmpty)
                }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("OpenHome")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { directProviders = model.directProviders.installed }
        .sheet(isPresented: $showingScanner) {
            ZStack(alignment: .topTrailing) {
                ActivationScannerView { value in
                    showingScanner = false
                    Task { await activate(scannedValue: value) }
                }
                Button { showingScanner = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(.black.opacity(0.65)).padding()
                    .accessibilityLabel("关闭扫描")
            }
            .ignoresSafeArea()
        }
    }

    @MainActor
    private func activate() async {
        isActivating = true; errorMessage = nil
        defer { isActivating = false }
        do {
            guard let baseURL = normalizedCenterURL(centerAddress) else { throw ActivationError.invalidAddress }
            let result = try await ActivationClient().activate(baseURL: baseURL, code: activationCode, deviceName: UIDevice.current.name)
            model.connection = try ConnectionStore().saveCenter(result)
            await model.validateCenter()
            activationCode = ""
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func activate(scannedValue: String) async {
        if let url = URL(string: scannedValue), url.scheme == "openhome" { await activate(url: url); return }
        activationCode = formattedActivationCode(scannedValue)
        showingManualActivation = true
    }

    @MainActor private func activate(url: URL) async {
        guard let values = URLComponents(url: url, resolvingAgainstBaseURL: false), url.scheme == "openhome", url.host == "activate",
              let address = values.queryItems?.first(where: { $0.name == "server" })?.value,
              let code = values.queryItems?.first(where: { $0.name == "code" })?.value else { errorMessage = "无法识别激活链接"; return }
        centerAddress = address
        activationCode = formattedActivationCode(code)
        await activate()
    }

    private func formattedActivationCode(_ value: String) -> String {
        let allowed = value.uppercased().filter { "23456789ABCDEFGHJKLMNPQRSTUVWXYZ".contains($0) }.prefix(8)
        return allowed.count > 4 ? "\(allowed.prefix(4))-\(allowed.dropFirst(4))" : String(allowed)
    }

    private func normalizedCenterURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"), components.host != nil else { return nil }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { components.path = "/api/v1" }
        else if path != "api/v1" && !path.hasSuffix("/api/v1") { components.path += "/api/v1" }
        return components.url
    }

}

private struct ActivationScannerView: UIViewControllerRepresentable {
    let onRecognized: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onRecognized: onRecognized) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], recognizesMultipleItems: false)
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onRecognized: (String) -> Void
        private var completed = false
        init(onRecognized: @escaping (String) -> Void) { self.onRecognized = onRecognized }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !completed else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    completed = true; dataScanner.stopScanning(); onRecognized(value); return
                }
            }
        }
    }
}

private struct ProviderModuleView: View {
    let module: AppModel.Module
    let factory: any ProviderFactory
    let directRegistry: DirectProviderRegistry?
    @Environment(AppModel.self) private var appModel
    @State private var authenticationRevision = 0

    @ViewBuilder
    var body: some View {
        switch module {
        case .gate:
            gateContent
        case .living:
            livingContent
        case .auto:
            autoContent
        case .lock:
            lockContent
        }
    }

    @ViewBuilder private var gateContent: some View {
        if let provider = try? factory.gateProvider() { GateView(provider: provider) } else { authenticationFallback }
    }

    @ViewBuilder private var livingContent: some View {
        if let provider = try? factory.dryerProvider() { DryerView(provider: provider, registrar: factory.liveActivityRegistrar()) } else { authenticationFallback }
    }

    @ViewBuilder private var autoContent: some View {
        if let provider = try? factory.vehicleProvider() { VehicleView(provider: provider, registrar: factory.liveActivityRegistrar()) } else { authenticationFallback }
    }

    @ViewBuilder private var lockContent: some View {
        if let provider = try? factory.lockProvider() { LockView(provider: provider) } else { authenticationFallback }
    }

    @ViewBuilder private var authenticationFallback: some View {
        if let authenticator = try? directRegistry?.authenticator(module.providerID) {
            DirectLoginView(module: module, authenticator: authenticator) {
                appModel.restoreModule(module.providerID)
                authenticationRevision += 1
            }
                .id(authenticationRevision)
        } else {
            ModuleUnavailableView(module: module, message: directRegistry == nil ? "连接配置不可用" : "登录组件不可用")
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
                Button(isBusy ? "正在登录…" : "登录") { Task { await signIn() } }.buttonStyle(.borderedProminent).controlSize(.large).disabled(account.isEmpty || secret.isEmpty || isBusy)
                if let message { Text(message).font(.caption).foregroundStyle(.red) }
            }.padding(20).background(Color.openHomeSurface, in: RoundedRectangle(cornerRadius: 18)).padding(14).frame(maxWidth: 520)
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

struct OpenHomeUnavailable: View {
    let title: String
    let systemImage: String
    let description: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if let actionTitle, let action {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(description)
            }             actions: {
                Button(actionTitle, action: action).buttonStyle(.bordered).controlSize(.large)
            }
        } else {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(description)
            }
        }
    }
}

func statusTone(_ value: String) -> Color {
    if value.contains("异常") || value.contains("故障") || value == "离线" || value == "差" { return .red }
    if value.contains("打开") || value.contains("未锁") || value.contains("较弱") || value == "信号一般" || value == "一般" || value == "设防中" || value == "已暂停" { return .orange }
    switch value {
    case "已熄火", "已启动", "行驶中", "充电中", "已关", "已关已锁", "正常", "已设防", "点亮", "信号良好", "良好", "在线", "纯电", "混动", "正在补能", "已充满", "好", "烘干中", "已完成", "已预约", "待机":
        return .green
    default:
        return .secondary
    }
}

func levelTone(_ percent: Double?) -> Color {
    guard let percent else { return .secondary }
    if percent <= 20 { return .red }
    if percent < 50 { return .orange }
    return .green
}

func batteryTone(_ raw: String?) -> Color {
    guard let raw, let percent = Int(raw.filter(\.isNumber)) else { return .secondary }
    return levelTone(Double(percent))
}

func openHomeDate(_ value: String) -> Date? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let date = VehicleDateParsing.parse(trimmed) { return date }
    if let number = Double(trimmed), number > 1_000_000_000 {
        return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
    }
    let normalized = trimmed
        .replacingOccurrences(of: "年", with: "-")
        .replacingOccurrences(of: "月", with: "-")
        .replacingOccurrences(of: "日", with: "")
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-M-d HH:mm:ss", "yyyy-M-d HH:mm", "MM-dd HH:mm:ss", "MM-dd HH:mm", "M-d HH:mm"] {
        formatter.dateFormat = format
        if let date = formatter.date(from: normalized) { return date }
    }
    return nil
}

func openHomeTimeText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: date)
}

extension Color {
    static let openHomeBackground = Color(uiColor: .systemGroupedBackground)
    static let openHomeSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let openHomeAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.78, green: 0.74, blue: 0.68, alpha: 1) : UIColor(red: 0.435, green: 0.396, blue: 0.349, alpha: 1)
    })
}
