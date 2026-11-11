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
        do { message = try await provider.open(resourceID: resource.id, idempotencyKey: UUID().uuidString).message }
        catch { message = error.localizedDescription }
    }

    func showPassword(_ resource: GateResource) async {
        guard busyID == nil else { return }
        busyID = resource.id; defer { busyID = nil }
        do {
            let value = try await provider.password(resourceID: resource.id)
            passwords[resource.id] = value
            UIPasteboard.general.string = value.password
            message = "密码已复制"
        } catch { message = error.localizedDescription }
    }

    func setSelected(_ resource: GateResource, selected: Bool) async {
        guard busyID == nil, resource.selected != selected else { return }
        busyID = resource.id; defer { busyID = nil }
        do {
            try await provider.setSelected(resourceID: resource.id, selected: selected)
            resources = try await provider.resources()
            message = selected ? "已加入常用门禁" : "已移出常用门禁"
        } catch { message = error.localizedDescription }
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
                Button("管理", systemImage: "slider.horizontal.3") { showingManagement = true }
                    .font(.subheadline.weight(.semibold))
                    .disabled(model.resources.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            VStack(spacing: 10) {
                ForEach(model.resources.filter { $0.selected && $0.passwordSupported }) { resource in
                    passwordCard(resource)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(model.resources.filter { $0.selected && !$0.passwordSupported }) { resource in
                        gateCard(resource)
                    }
                }
            }
            .padding(14).frame(maxWidth: 520)
            if model.isLoading { ProgressView().tint(.openHomeGate) }
            if !model.isLoading && model.resources.filter(\.selected).isEmpty { ContentUnavailableView("暂无常用门禁", systemImage: "door.left.hand.closed") }
        }
        .overlay(alignment: .bottom) { if let message = model.message { Text(message).font(.footnote.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 16) } }
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $showingManagement) { GateManagementView(model: model) }
    }

    private func gateCard(_ resource: GateResource) -> some View {
        Button { Task { await model.open(resource) } } label: {
            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: "lock.open").frame(width: 42, height: 42).background(Color.openHomeGate, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                resourceName(resource, large: false)
            }.frame(maxWidth: .infinity, minHeight: 112, alignment: .leading).padding(14).background(Color.openHomeGate.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(model.busyID != nil)
    }

    private func passwordCard(_ resource: GateResource) -> some View {
        HStack(spacing: 10) {
            Button { Task { await model.open(resource) } } label: {
                HStack(spacing: 12) { Image(systemName: "lock.open").frame(width: 42, height: 42).background(Color.openHomeGate, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white); resourceName(resource, large: true) }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading).layoutPriority(1)
            }.buttonStyle(.plain)
            Button { Task { await model.showPassword(resource) } } label: {
                if let value = model.passwords[resource.id] {
                    VStack(spacing: 3) { Text(value.password).font(.system(.title3, design: .monospaced).weight(.bold)).tracking(2); Text(value.validUntil, style: .timer).font(.caption2.monospacedDigit()) }
                } else { VStack(spacing: 4) { Image(systemName: "key"); Text("查看密码").font(.caption.bold()) } }
            }.frame(width: 108).frame(minHeight: 76).background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14)).buttonStyle(.plain)
        }.padding(10).background(Color.openHomeGate.opacity(0.10), in: RoundedRectangle(cornerRadius: 18)).disabled(model.busyID != nil)
    }

    private func resourceName(_ resource: GateResource, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(resource.name).font(large ? .title3.bold() : .headline).lineLimit(1); if let community = resource.communityName { Text(community).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
    }
}

private struct GateManagementView: View {
    let model: GateViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !model.resources.filter(\.selected).isEmpty {
                    Section("常用门禁") {
                        ForEach(model.resources.filter(\.selected)) { resource in row(resource) }
                    }
                }
                Section("全部门禁") {
                    ForEach(model.resources.filter { !$0.selected }) { resource in row(resource) }
                }
            }
            .navigationTitle("门禁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ resource: GateResource) -> some View {
        Button { Task { await model.setSelected(resource, selected: !resource.selected) } } label: {
            HStack(spacing: 12) {
                Image(systemName: "door.left.hand.open").frame(width: 32, height: 32).background(Color.openHomeGate.opacity(0.12), in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(Color.openHomeGate)
                VStack(alignment: .leading, spacing: 2) {
                    Text(resource.name).foregroundStyle(.primary)
                    if let community = resource.communityName { Text(community).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if model.busyID == resource.id { ProgressView() }
                else { Image(systemName: resource.selected ? "star.fill" : "star").foregroundStyle(resource.selected ? Color.openHomeGate : .secondary) }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busyID != nil)
    }
}

private extension Color { static let openHomeGate = Color(red: 0.604, green: 0.353, blue: 0.271) }
