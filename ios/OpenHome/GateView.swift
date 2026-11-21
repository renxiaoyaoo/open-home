import Observation
import SwiftUI
import UIKit
import AudioToolbox

@MainActor
@Observable
final class GateViewModel {
    var resources: [GateResource] = []
    var isLoading = false
    var busyID: String?
    var message: String?
    var passwords: [String: GatePassword] = [:]
    private let provider: any GateProvider
    private var messageGeneration = 0

    init(provider: any GateProvider) {
        self.provider = provider
        resources = ModuleContentStore.load("gate-resources.json", as: [GateResource].self) ?? []
        passwords = ShownGatePasswords.values
    }

    func discardDisplayedContent() {
        resources = []
        message = nil
        if ModuleContentStore.isBlocked("gate-resources.json") {
            passwords = [:]
            ShownGatePasswords.values = [:]
        }
    }

    func load() async {
        let revision = ModuleContentStore.revision
        guard !ModuleContentStore.isBlocked("gate-resources.json") else { discardDisplayedContent(); return }
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await provider.resources()
            guard revision == ModuleContentStore.revision, !ModuleContentStore.isBlocked("gate-resources.json") else { discardDisplayedContent(); return }
            resources = value
            ModuleContentStore.save("gate-resources.json", resources)
        }
        catch is CancellationError { return }
        catch let error as URLError where error.code == .cancelled { return }
        catch let error as APIError {
            if case .providerAuthenticationRequired = error { discardDisplayedContent() }
            message = error.localizedDescription
        }
        catch { message = error.localizedDescription }
    }

    func open(_ resource: GateResource) async {
        guard busyID == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        busyID = resource.id; defer { busyID = nil }
        do {
            let result = try await provider.open(resourceHandle: resource.handle, idempotencyKey: UUID().uuidString)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(1104)
            notify(result.message.isEmpty ? "\(resource.name) 已开门" : result.message, kind: .success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            notify(error.localizedDescription, kind: .error)
        }
    }

    func showPassword(_ resource: GateResource) async {
        if let value = passwords[resource.id] { copy(value.password); return }
        guard busyID == nil else { return }
        busyID = resource.id; defer { busyID = nil }
        do {
            let value = try await provider.password(resourceHandle: resource.handle)
            passwords[resource.id] = value
            ShownGatePasswords.values[resource.id] = value
            copy(value.password)
        } catch { notify(error.localizedDescription) }
    }

    func copy(_ password: String) {
        UIPasteboard.general.string = password
        notify("密码已复制")
    }

    func setFavorite(_ resource: GateResource, selected: Bool) async {
        guard !resource.isPinned, resource.selected != selected, busyID == nil else { return }
        let snapshot = resources
        busyID = resource.id
        defer { busyID = nil }
        do {
            let revision = ModuleContentStore.revision
            let value = try await provider.setSelected(resourceHandle: resource.handle, selected: selected)
            guard revision == ModuleContentStore.revision else { discardDisplayedContent(); return }
            resources = value
            ModuleContentStore.save("gate-resources.json", resources)
            notify(selected ? "已加入常用门禁" : "已移出常用门禁", kind: .success)
        } catch is CancellationError { resources = snapshot }
        catch let error as URLError where error.code == .cancelled { resources = snapshot }
        catch { resources = snapshot; notify(error.localizedDescription, kind: .error) }
    }
    enum NoticeKind { case success, error, neutral }
    var noticeKind: NoticeKind = .neutral
    private func notify(_ value: String, kind: NoticeKind = .neutral) {
        messageGeneration += 1
        let generation = messageGeneration
        noticeKind = kind
        message = value
        Task { try? await Task.sleep(for: .seconds(3)); guard generation == messageGeneration else { return }; message = nil }
    }
}

struct GateView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: GateViewModel
    @State private var managingCommunity: String?

    init(provider: any GateProvider) { _model = State(initialValue: GateViewModel(provider: provider)) }

    var body: some View {
        Group {
            if model.isLoading && model.resources.isEmpty { ProgressView("正在读取门禁").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if model.resources.isEmpty { ContentUnavailableView("还没有门禁", systemImage: "door.left.hand.closed", description: Text(model.message ?? "")) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(communities, id: \.name) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(group.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                    Spacer()
                                    Button("全部") { managingCommunity = group.name }.font(.body)
                                }
                                .padding(.horizontal, 4)
                                VStack(spacing: 0) {
                                    if group.items.isEmpty {
                                        Text("暂无常用").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                    } else {
                                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, resource in
                                            gateButton(resource)
                                            if index < group.items.count - 1 { Divider().padding(.leading, 18) }
                                        }
                                    }
                                }
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .overlay(alignment: .bottom) { if let message = model.message { gateNotice(message).padding(.bottom, 16) } }
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: appModel.sessionRevision) { _, _ in model.discardDisplayedContent() }
        .sheet(isPresented: Binding(get: { managingCommunity != nil }, set: { if !$0 { managingCommunity = nil } })) {
            if let managingCommunity { GateManagementView(model: model, community: managingCommunity) }
        }
    }

    private var communities: [(name: String, items: [GateResource])] {
        grouped(model.resources).map { group in
            let visible = group.items.enumerated().filter { $0.element.selected || $0.element.isPinned }.sorted { lhs, rhs in
                if lhs.element.isPinned != rhs.element.isPinned { return lhs.element.isPinned }
                return lhs.offset < rhs.offset
            }.map(\.element)
            return (name: group.name, items: visible)
        }
    }

    private func gateButton(_ resource: GateResource) -> some View {
        let shown = ShownGatePasswords.values[resource.id] ?? model.passwords[resource.id]
        let showsKey = resource.passwordSupported || shown != nil
        return HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: resource.isPinned ? "building.2" : "door.left.hand.open")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                Text(resource.name).font(.system(size: 28, weight: .semibold)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { Task { await model.open(resource) } }
            if let value = shown {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value.password).font(.system(size: 28, weight: .semibold, design: .monospaced)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.6)
                    countdown(value.validUntil).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: showsKey ? 60 : 16))
        .overlay(alignment: .trailing) {
            if showsKey { keyButton(resource).padding(.trailing, 8) }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
    }
    private func keyButton(_ resource: GateResource) -> some View {
        let shown = ShownGatePasswords.values[resource.id] ?? model.passwords[resource.id]
        return Button {
            if let value = shown { model.copy(value.password) }
            else { Task { await model.showPassword(resource) } }
        } label: {
            ZStack {
                Image(uiImage: GateSymbols.key).renderingMode(.template).opacity(shown == nil ? 1 : 0)
                Image(uiImage: GateSymbols.copy).renderingMode(.template).opacity(shown == nil ? 0 : 1)
            }
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(SteadyButtonStyle())
        .accessibilityLabel(shown == nil ? "查看密码" : "复制密码")
    }
    private func countdown(_ date: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(date.timeIntervalSince(context.date)))
            Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
        }
    }
    private func gateNotice(_ message: String) -> some View {
        let success = model.noticeKind == .success
        let error = model.noticeKind == .error
        return Label(message, systemImage: success ? "checkmark.circle.fill" : error ? "xmark.octagon.fill" : "info.circle.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 13)
            .background(success ? Color.green : error ? Color.red : Color.primary.opacity(0.82), in: Capsule())
            .shadow(radius: 8, y: 3)
    }

    private func grouped(_ resources: [GateResource]) -> [(name: String, items: [GateResource])] {
        var groups: [(name: String, items: [GateResource])] = []
        for resource in resources {
            let name = communityName(resource)
            if let index = groups.firstIndex(where: { $0.name == name }) { groups[index].items.append(resource) }
            else { groups.append((name: name, items: [resource])) }
        }
        return groups
    }

    private func communityName(_ resource: GateResource) -> String {
        let value = resource.communityName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "其他门禁" : value
    }
}

private struct GateManagementView: View {
    let model: GateViewModel
    let community: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(community) {
                    ForEach(allDoors) { resource in managementRow(resource) }
                }
            }
            .environment(\.defaultMinListRowHeight, 52)
            .navigationTitle("全部门禁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var scoped: [GateResource] { model.resources.filter { $0.communityTitle == community } }
    private var allDoors: [GateResource] {
        scoped.enumerated().sorted { left, right in
            if left.element.isPinned != right.element.isPinned { return left.element.isPinned }
            if left.element.selected != right.element.selected { return left.element.selected }
            return left.offset < right.offset
        }.map(\.element)
    }

    private func managementRow(_ resource: GateResource) -> some View {
        HStack(spacing: 12) {
            Button { Task { await model.open(resource) } } label: {
                HStack(spacing: 12) {
                    Image(systemName: resource.isPinned ? "building.2" : "door.left.hand.open")
                        .foregroundStyle(.secondary).frame(width: 28)
                    Text(resource.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)
            if model.busyID == resource.id { ProgressView().controlSize(.small) }
            Button {
                Task {
                    await model.setFavorite(resource, selected: !resource.selected)
                }
            } label: {
                Image(systemName: resource.selected || resource.isPinned ? "star.fill" : "star")
                    .font(.title3).foregroundStyle(resource.selected || resource.isPinned ? Color.openHomeGate : .secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(resource.isPinned || model.busyID != nil)
            .accessibilityLabel(resource.isPinned ? "常驻门禁" : resource.selected ? "取消常用" : "加入常用")
        }
    }
}

private enum GateSymbols {
    static let key = UIImage(systemName: "key", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)) ?? UIImage()
    static let copy = UIImage(systemName: "doc.on.doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)) ?? UIImage()
}

private struct SteadyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

private enum ShownGatePasswords {
    static var values: [String: GatePassword] = [:]
}

private extension GateResource {
    var communityTitle: String {
        let value = communityName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "其他门禁" : value
    }
    var isPinned: Bool { pinned == true }
}

private extension Color { static let openHomeGate = Color(red: 0.604, green: 0.353, blue: 0.271) }
