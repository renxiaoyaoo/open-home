import Observation
import SwiftUI
import UIKit

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
            resources = applyingOrder(value, favorites: savedFavoriteOrder())
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
        busyID = resource.id; defer { busyID = nil }
        do { notify(try await provider.open(resourceID: resource.id, idempotencyKey: UUID().uuidString).message) }
        catch { notify(error.localizedDescription) }
    }

    func showPassword(_ resource: GateResource) async {
        if let value = passwords[resource.id] { copy(value.password); return }
        guard busyID == nil else { return }
        busyID = resource.id; defer { busyID = nil }
        do {
            let value = try await provider.password(resourceID: resource.id)
            passwords[resource.id] = value
            ShownGatePasswords.values[resource.id] = value
            copy(value.password)
        } catch { notify(error.localizedDescription) }
    }

    func copy(_ password: String) {
        UIPasteboard.general.string = password
        notify("密码已复制")
    }

    func setSelected(_ resource: GateResource, selected: Bool) async {
        guard busyID == nil, resource.selected != selected else { return }
        busyID = resource.id; defer { busyID = nil }
        do {
            try await provider.setSelected(resourceID: resource.id, selected: selected)
            resources = try await provider.resources()
            ModuleContentStore.save("gate-resources.json", resources)
            notify(selected ? "已加入常用门禁" : "已移出常用门禁")
        } catch is CancellationError { return }
        catch let error as URLError where error.code == .cancelled { return }
        catch { notify(error.localizedDescription) }
    }

    func moveFavorite(_ draggedID: String, before targetID: String?, community: String) async {
        guard let resource = resources.first(where: { $0.id == draggedID }), !resource.staysPut, resource.communityTitle == community else { return }
        var ids = resources.filter { $0.communityTitle == community && $0.selected && !$0.staysPut }.map(\.id)
        let inserting = !ids.contains(draggedID)
        ids.removeAll { $0 == draggedID }
        if let targetID, let index = ids.firstIndex(of: targetID) { ids.insert(draggedID, at: index) }
        else { ids.append(draggedID) }
        if inserting {
            while ids.count > 2, let index = ids.firstIndex(where: { $0 != draggedID }) { ids.remove(at: index) }
        }
        await replaceFavorites(in: community, ids: ids)
    }

    func removeFavorite(_ draggedID: String, community: String) async {
        guard resources.contains(where: { $0.id == draggedID && $0.selected && !$0.staysPut && $0.communityTitle == community }) else { return }
        await replaceFavorites(in: community, ids: resources.filter { $0.communityTitle == community && $0.selected && !$0.staysPut && $0.id != draggedID }.map(\.id))
    }

    func reorderFavorites(in community: String, from source: IndexSet, to destination: Int) async {
        var ids = resources.filter { $0.communityTitle == community && $0.selected && !$0.staysPut }.map(\.id)
        guard source.allSatisfy({ ids.indices.contains($0) }) else { return }
        ids.move(fromOffsets: source, toOffset: destination)
        await replaceFavorites(in: community, ids: ids)
    }

    func deleteFavorites(in community: String, at offsets: IndexSet) async {
        var ids = resources.filter { $0.communityTitle == community && $0.selected && !$0.staysPut }.map(\.id)
        ids.remove(atOffsets: offsets)
        await replaceFavorites(in: community, ids: ids)
    }

    func addFavorite(_ id: String, community: String) async {
        guard let resource = resources.first(where: { $0.id == id }), !resource.staysPut, resource.communityTitle == community else { return }
        var ids = resources.filter { $0.communityTitle == community && $0.selected && !$0.staysPut }.map(\.id)
        guard !ids.contains(id) else { return }
        let capacity = max(ids.count, 1)
        ids.append(id)
        while ids.count > capacity { ids.removeFirst() }
        await replaceFavorites(in: community, ids: ids)
    }

    private func replaceFavorites(in community: String, ids: [String]) async {
        let currentCommunity = resources.filter { $0.communityTitle == community && $0.selected && !$0.staysPut }.map(\.id)
        guard ids != currentCommunity, busyID == nil else { return }
        var next: [String] = []
        var placed = false
        for resource in resources where resource.selected && !resource.staysPut {
            if resource.communityTitle == community {
                if !placed { next.append(contentsOf: ids); placed = true }
            } else { next.append(resource.id) }
        }
        if !placed { next.append(contentsOf: ids) }
        let current = resources.filter { $0.selected && !$0.staysPut }.map(\.id)
        guard next != current else { return }
        let snapshot = resources
        let previousOrder = savedFavoriteOrder()
        resources = arranged(resources, favorites: next)
        saveFavoriteOrder(next)
        busyID = "reorder"
        defer { busyID = nil }
        do {
            try await provider.setOrder(ids: next, previousIDs: current)
            let revision = ModuleContentStore.revision
            let value = try await provider.resources()
            guard revision == ModuleContentStore.revision else { discardDisplayedContent(); return }
            resources = applyingOrder(value, favorites: next)
            ModuleContentStore.save("gate-resources.json", resources)
        } catch is CancellationError { resources = snapshot; saveFavoriteOrder(previousOrder) }
        catch let error as URLError where error.code == .cancelled { resources = snapshot; saveFavoriteOrder(previousOrder) }
        catch { resources = snapshot; saveFavoriteOrder(previousOrder); notify(error.localizedDescription) }
    }

    private func savedFavoriteOrder() -> [String] { ModuleContentStore.load("gate-favorite-order.json", as: [String].self) ?? [] }
    private func saveFavoriteOrder(_ ids: [String]) { ModuleContentStore.save("gate-favorite-order.json", ids) }
    private func applyingOrder(_ resources: [GateResource], favorites: [String]) -> [GateResource] {
        guard !favorites.isEmpty else { return resources }
        let rank = Dictionary(uniqueKeysWithValues: favorites.enumerated().map { ($1, $0) })
        var groups: [(key: String, items: [GateResource])] = []
        for resource in resources {
            let key = resource.communityTitle
            if let index = groups.firstIndex(where: { $0.key == key }) { groups[index].items.append(resource) }
            else { groups.append((key, [resource])) }
        }
        return groups.flatMap { group in
            let leading = group.items.filter { rank[$0.id] != nil }.sorted { rank[$0.id, default: 0] < rank[$1.id, default: 0] }
            let rest = group.items.filter { rank[$0.id] == nil }
            return leading + rest
        }
    }

    private func arranged(_ resources: [GateResource], favorites: [String]) -> [GateResource] {
        let byID = Dictionary(uniqueKeysWithValues: resources.map { ($0.id, $0) })
        var used = Set<String>()
        var ordered: [GateResource] = []
        for id in favorites {
            guard let resource = byID[id], !resource.staysPut else { continue }
            ordered.append(resource.selecting(true)); used.insert(id)
        }
        for resource in resources where !used.contains(resource.id) {
            ordered.append(resource.staysPut ? resource : resource.selecting(false))
        }
        return ordered
    }

    private func notify(_ value: String) {
        messageGeneration += 1
        let generation = messageGeneration
        message = value
        Task { try? await Task.sleep(for: .seconds(2.2)); guard generation == messageGeneration else { return }; message = nil }
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
                                    Button("管理") { managingCommunity = group.name }.font(.body)
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
        .overlay(alignment: .bottom) { if let message = model.message { Text(message).font(.footnote.weight(.medium)).foregroundStyle(gateNoticeTone(message)).padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 16) } }
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: appModel.sessionRevision) { _, _ in model.discardDisplayedContent() }
        .sheet(isPresented: Binding(get: { managingCommunity != nil }, set: { if !$0 { managingCommunity = nil } })) {
            if let managingCommunity { GateManagementView(model: model, community: managingCommunity) }
        }
    }

    private var communities: [(name: String, items: [GateResource])] {
        grouped(model.resources).map { group in
            let visible = group.items.enumerated().filter { $0.element.selected || $0.element.staysPut }.sorted { lhs, rhs in
                if lhs.element.staysPut != rhs.element.staysPut { return lhs.element.staysPut }
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
                Image(systemName: resource.staysPut ? "building.2" : "door.left.hand.open")
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

    private func gateCard(_ resource: GateResource) -> some View {
        Button { Task { await model.open(resource) } } label: {
            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: "lock.open").frame(width: 42, height: 42).background(Color.openHomeGate, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                Text(resource.name).font(.title3.weight(.semibold)).lineLimit(2)
            }.frame(maxWidth: .infinity, minHeight: 112, alignment: .leading).padding(14).background(Color.openHomeSurface, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(model.busyID != nil)
    }

    private func passwordCard(_ resource: GateResource) -> some View {
        HStack(spacing: 10) {
            Button { Task { await model.open(resource) } } label: {
                HStack(spacing: 12) { Image(systemName: "lock.open").frame(width: 42, height: 42).background(Color.openHomeGate, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white); Text(resource.name).font(.title3.weight(.semibold)).lineLimit(2) }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading).layoutPriority(1)
            }.buttonStyle(.plain)
            Button { Task { await model.showPassword(resource) } } label: {
                if let value = model.passwords[resource.id] {
                    VStack(spacing: 3) { Text(value.password).font(.system(.title3, design: .monospaced).weight(.bold)).tracking(2); Text(value.validUntil, style: .timer).font(.caption2.monospacedDigit()) }
                } else { VStack(spacing: 4) { Image(systemName: "key"); Text("查看密码").font(.caption.bold()) } }
            }.frame(width: 108).frame(minHeight: 76).background(Color.openHomeSurface, in: RoundedRectangle(cornerRadius: 14)).buttonStyle(.plain)
        }.padding(10).background(Color.openHomeSurface, in: RoundedRectangle(cornerRadius: 18)).disabled(model.busyID != nil)
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
                if !fixedDoors.isEmpty {
                    Section("单元门") {
                        ForEach(fixedDoors) { resource in managementRow(resource) }
                    }
                }
                Section("常用") {
                    if favorites.isEmpty { Text("暂无常用").foregroundStyle(.secondary) }
                    ForEach(favorites) { resource in managementRow(resource) }
                        .onMove { source, destination in Task { await model.reorderFavorites(in: community, from: source, to: destination) } }
                        .onDelete { offsets in Task { await model.deleteFavorites(in: community, at: offsets) } }
                }
                Section("大门") {
                    if movableDoors.isEmpty { Text("暂无大门").foregroundStyle(.secondary) }
                    ForEach(movableDoors) { resource in
                        managementRow(resource, add: true)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .environment(\.defaultMinListRowHeight, 52)
            .overlay(alignment: .bottom) { if let message = model.message { Text(message).font(.footnote.weight(.medium)).foregroundStyle(gateNoticeTone(message)).padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 16) } }
            .navigationTitle(community)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var scoped: [GateResource] { model.resources.filter { $0.communityTitle == community } }
    private var favorites: [GateResource] { scoped.filter { $0.selected && !$0.staysPut } }
    private var movableDoors: [GateResource] { scoped.filter { !$0.selected && !$0.staysPut } }
    private var fixedDoors: [GateResource] { scoped.filter(\.staysPut) }

    private func managementRow(_ resource: GateResource, add: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(resource.name).font(.body).lineLimit(2)
            Spacer(minLength: 8)
            if model.busyID == resource.id || model.busyID == "reorder" { ProgressView().controlSize(.small) }
            if add {
                Button { Task { await model.addFavorite(resource.id, community: community) } } label: {
                    Image(systemName: "plus.circle").font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("加入常用")
            }
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

private func gateNoticeTone(_ message: String) -> Color {
    if message.contains("失败") || message.contains("错误") || message.contains("无法") || message.contains("无效") { return .red }
    if message.contains("已复制") || message.contains("成功") || message.contains("已开门") || message.contains("已加入") || message.contains("已移出") { return .green }
    return .primary
}

private enum ShownGatePasswords {
    static var values: [String: GatePassword] = [:]
}

private extension GateResource {
    var communityTitle: String {
        let value = communityName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "其他门禁" : value
    }
    var staysPut: Bool { name.contains("单元") || name.contains("楼栋") }
    func selecting(_ selected: Bool) -> GateResource {
        GateResource(id: id, name: name, communityName: communityName, passwordSupported: passwordSupported, providerFeatured: providerFeatured, selected: selected, refreshedAt: refreshedAt)
    }
}

private extension Color { static let openHomeGate = Color(red: 0.604, green: 0.353, blue: 0.271) }
