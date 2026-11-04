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
        if let url = model.connection?.centerURL {
            let client = APIClient(baseURL: url, credential: { try ConnectionStore().centerToken() })
            switch model.selectedModule {
            case .gate: GateView(provider: RemoteGateProvider(client: client))
            case .living: DryerView(provider: RemoteDryerProvider(client: client))
            default: ModulePlaceholder(module: model.selectedModule)
            }
        } else { ModulePlaceholder(module: model.selectedModule) }
    }

    private var moduleSwitcher: some View {
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
            }.padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden).contentMargins(.vertical, 12)
        .background(.thinMaterial)
    }
}

private struct ConnectionSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: ConnectionMode = .center
    @State private var activationCode = ""
    @State private var isActivating = false
    @State private var errorMessage: String?

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
                        Text("账号会话只保存在本机 Keychain。每个厂商 Provider 独立安装和登录。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("选择 Provider") { model.connection = .init(mode: .direct, centerURL: nil, deviceCredentialID: nil, enabledProviders: []) }.buttonStyle(OpenHomePrimaryButton())
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

private struct ModulePlaceholder: View {
    let module: AppModel.Module
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: module.symbol).font(.system(size: 34)).foregroundStyle(Color.openHomeAccent)
            Text(module.rawValue).font(.title2.bold())
            Text("Provider 已就绪后在这里显示实时状态").font(.subheadline).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: 520).background(.white, in: RoundedRectangle(cornerRadius: 18)).padding(14)
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
