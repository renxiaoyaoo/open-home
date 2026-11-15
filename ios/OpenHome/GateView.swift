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
    private var messageTask: Task<Void, Never>?

    init(provider: any GateProvider) { self.provider = provider }

    func load() async {
        isLoading = true; message = nil
        defer { isLoading = false }
        do { resources = try await provider.resources() }
        catch { message = error.localizedDescription }
    }

    func open(_ resource: GateResource) async {
        guard busyID == nil else { return }
        busyID = resource.id; defer { busyID = nil }
        do { notify(try await provider.open(resourceID: resource.id, idempotencyKey: UUID().uuidString).message) }
        catch { notify(error.localizedDescription) }
    }

    func showPassword(_ resource: GateResource) async {
        guard busyID == nil else { return }
        busyID = resource.id; defer { busyID = nil }
        do {
            let value = try await provider.password(resourceID: resource.id)
            passwords[resource.id] = value
            UIPasteboard.general.string = value.password
            notify("密码已复制")
        } catch { notify(error.localizedDescription) }
    }

    func setSelected(_ resource: GateResource, selected: Bool) async {
        guard busyID == nil, resource.selected != selected else { return }
        busyID = resource.id; defer { busyID = nil }
        do {
            try await provider.setSelected(resourceID: resource.id, selected: selected)
            resources = try await provider.resources()
            notify(selected ? "已加入常用门禁" : "已移出常用门禁")
        } catch { notify(error.localizedDescription) }
    }

    private func notify(_ value: String) {
        messageTask?.cancel(); message = value
        messageTask = Task { try? await Task.sleep(for: .seconds(2.2)); guard !Task.isCancelled else { return }; message = nil }
    }
}

struct GateView: View {
    @State private var model: GateViewModel
    @State private var showingManagement = false

    init(provider: any GateProvider) { _model = State(initialValue: GateViewModel(provider: provider)) }

    var body: some View {
        ScrollView {
            HStack {
                Spacer()
                Button("全部", systemImage: "list.bullet") { showingManagement = true }
                    .font(.subheadline.weight(.semibold))
                    .disabled(model.resources.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            VStack(spacing: 10) {
                ForEach(grouped(model.resources.filter(\.selected)), id: \.name) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name).font(.title3.bold()).padding(.horizontal, 2)
                        ForEach(group.items.filter(\.passwordSupported)) { resource in passwordCard(resource) }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(group.items.filter { !$0.passwordSupported }) { resource in gateCard(resource) }
                        }
                    }
                }
            }
            .padding(14).frame(maxWidth: 520)
            if model.isLoading { ProgressView().tint(.openHomeGate) }
            if !model.isLoading && model.resources.filter(\.selected).isEmpty { ContentUnavailableView("暂无常用门禁", systemImage: "door.left.hand.closed") }
        }
        .overlay(alignment: .bottom) { if let message = model.message { Text(message).font(.footnote.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 16) } }
        .task { if model.resources.isEmpty { await model.load() } }
        .refreshable { await model.load() }
        .sheet(isPresented: $showingManagement) { GateManagementView(model: model) }
    }

    private func gateCard(_ resource: GateResource) -> some View {
        Button { Task { await model.open(resource) } } label: {
            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: "lock.open").frame(width: 42, height: 42).background(Color.openHomeGate, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                Text(resource.name).font(.title3.bold()).lineLimit(2)
            }.frame(maxWidth: .infinity, minHeight: 112, alignment: .leading).padding(14).background(Color.openHomeGate.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(model.busyID != nil)
    }

    private func passwordCard(_ resource: GateResource) -> some View {
        HStack(spacing: 10) {
            Button { Task { await model.open(resource) } } label: {
                HStack(spacing: 12) { Image(systemName: "lock.open").frame(width: 42, height: 42).background(Color.openHomeGate, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white); Text(resource.name).font(.title3.bold()).lineLimit(2) }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading).layoutPriority(1)
            }.buttonStyle(.plain)
            Button { Task { await model.showPassword(resource) } } label: {
                if let value = model.passwords[resource.id] {
                    VStack(spacing: 3) { Text(value.password).font(.system(.title3, design: .monospaced).weight(.bold)).tracking(2); Text(value.validUntil, style: .timer).font(.caption2.monospacedDigit()) }
                } else { VStack(spacing: 4) { Image(systemName: "key"); Text("查看密码").font(.caption.bold()) } }
            }.frame(width: 108).frame(minHeight: 76).background(Color.openHomeSurface, in: RoundedRectangle(cornerRadius: 14)).buttonStyle(.plain)
        }.padding(10).background(Color.openHomeGate.opacity(0.10), in: RoundedRectangle(cornerRadius: 18)).disabled(model.busyID != nil)
    }

    private func grouped(_ resources: [GateResource]) -> [(name: String, items: [GateResource])] {
        Dictionary(grouping: resources, by: communityName)
            .map { (name: $0.key, items: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func communityName(_ resource: GateResource) -> String {
        let value = resource.communityName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "其他门禁" : value
    }
}

private struct GateManagementView: View {
    let model: GateViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedResources, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.items) { resource in row(resource) }
                    }
                }
            }
            .navigationTitle("全部门禁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ resource: GateResource) -> some View {
        HStack(spacing: 12) {
            Button { Task { await model.open(resource) } } label: {
                HStack(spacing: 12) {
                Image(systemName: "door.left.hand.open").frame(width: 32, height: 32).background(Color.openHomeGate.opacity(0.12), in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(Color.openHomeGate)
                VStack(alignment: .leading, spacing: 2) {
                    Text(resource.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text("轻点开门").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                }
            }
            .buttonStyle(.plain)
            Button { Task { await model.setSelected(resource, selected: !resource.selected) } } label: {
                Image(systemName: resource.selected ? "star.fill" : "star").font(.title3).foregroundStyle(resource.selected ? Color.openHomeGate : .secondary).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(resource.selected ? "取消常用" : "加入常用")
            if model.busyID == resource.id { ProgressView().controlSize(.small) }
        }.disabled(model.busyID != nil)
    }

    private var groupedResources: [(name: String, items: [GateResource])] {
        Dictionary(grouping: model.resources) { resource in
            let value = resource.communityName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? "其他门禁" : value
        }
        .map { (name: $0.key, items: $0.value.sorted { left, right in left.selected != right.selected ? left.selected : left.name.localizedStandardCompare(right.name) == .orderedAscending }) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private extension Color { static let openHomeGate = Color(red: 0.604, green: 0.353, blue: 0.271) }
