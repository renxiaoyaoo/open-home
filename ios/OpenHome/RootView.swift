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
                    else { ModulePlaceholder(module: model.selectedModule) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.openHomeBackground)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.openHomeAccent)
    }

    private var moduleSwitcher: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(AppModel.Module.allCases) { module in
                    Button { model.selectedModule = module } label: {
                        HStack(spacing: 7) {
                            Image(systemName: module.symbol).frame(width: 24, height: 24).background(.white.opacity(model.selectedModule == module ? 0.18 : 1), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(module.rawValue).font(.system(size: 12, weight: .semibold))
                                Text(module.subtitle).font(.system(size: 9))
                            }
                        }
                        .foregroundStyle(model.selectedModule == module ? .white : .primary)
                        .padding(.horizontal, 10).frame(height: 48)
                        .background(model.selectedModule == module ? Color.openHomeAccent : .white, in: RoundedRectangle(cornerRadius: 13))
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
                        TextField("激活码", text: $activationCode).textInputAutocapitalization(.characters).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                        Button("继续") { /* Activation exchange lands here once the API contract is available. */ }.buttonStyle(OpenHomePrimaryButton()).disabled(activationCode.isEmpty)
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
