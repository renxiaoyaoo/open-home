import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class LockViewModel {
    var devices: [LockDevice] = []
    var selectedDeviceID = ""
    var detail: LockDetail?
    var events: [LockEvent] = []
    var temporaryPassword: LockTemporaryPassword?
    var isLoading = false
    var isCreatingPassword = false
    var message: String?
    private let provider: any LockProvider

    init(provider: any LockProvider) { self.provider = provider }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            if devices.isEmpty {
                devices = try await provider.devices()
                selectedDeviceID = devices.first?.id ?? ""
            }
            guard !selectedDeviceID.isEmpty else { throw ProviderError.invalidResponse }
            async let nextDetail = provider.detail(deviceID: selectedDeviceID)
            async let nextEvents = provider.dynamics(deviceID: selectedDeviceID, cursor: nil)
            detail = try await nextDetail
            events = try await nextEvents.items
            message = nil
        } catch { message = error.localizedDescription }
    }

    func select(_ id: String) async {
        selectedDeviceID = id; detail = nil; events = []; temporaryPassword = nil
        await load()
    }

    func createPassword() async {
        guard !selectedDeviceID.isEmpty, !isCreatingPassword else { return }
        isCreatingPassword = true; defer { isCreatingPassword = false }
        do {
            let value = try await provider.createTemporaryPassword(deviceID: selectedDeviceID)
            temporaryPassword = value
            UIPasteboard.general.string = value.password
            message = nil
        } catch { message = error.localizedDescription }
    }
}

struct LockView: View {
    @State private var model: LockViewModel
    init(provider: any LockProvider) { _model = State(initialValue: LockViewModel(provider: provider)) }

    var body: some View {
        ScrollView {
            if let detail = model.detail {
                VStack(spacing: 12) {
                    status(detail)
                    passwordCard
                    eventsCard
                }.padding(14).frame(maxWidth: 520)
            } else if model.isLoading {
                ProgressView().padding(.top, 100)
            } else {
                ContentUnavailableView("门锁暂时未加载", systemImage: "lock.shield", description: Text(model.message ?? "下拉重试"))
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func status(_ detail: LockDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(detail.name ?? model.devices.first(where: { $0.id == model.selectedDeviceID })?.name ?? "智能门锁").font(.title3.bold())
                    Text(detail.wifiName ?? "Wi‑Fi").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if model.devices.count > 1 {
                    Menu { ForEach(model.devices) { device in Button(device.name) { Task { await model.select(device.id) } } } } label: { Image(systemName: "chevron.up.chevron.down") }
                }
            }
            HStack(spacing: 10) {
                metric("门锁", detail.battery.map { "\($0)%" } ?? "—", "battery.75percent")
                metric("猫眼", detail.cameraBattery.map { "\($0)%" } ?? "—", "camera")
                metric("信号", detail.wifiSignal ?? "—", "wifi")
            }
        }.padding(18).foregroundStyle(.white).background(Color.openHomeLock, in: RoundedRectangle(cornerRadius: 18))
    }

    private var passwordCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill").frame(width: 42, height: 42).background(Color.openHomeLock.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("一次性临时密码").font(.caption).foregroundStyle(.secondary)
                if let value = model.temporaryPassword {
                    Text(value.password).font(.system(.title3, design: .monospaced, weight: .semibold)).tracking(2)
                    Text("有效至 \(value.expiresAt.formatted(date: .omitted, time: .shortened)) · 已复制").font(.caption2).foregroundStyle(.secondary)
                } else { Text("生成后自动复制").font(.subheadline.weight(.medium)) }
            }
            Spacer()
            Button(model.temporaryPassword == nil ? "查看密码" : "重新生成") { Task { await model.createPassword() } }
                .buttonStyle(.borderedProminent).tint(.openHomeLock).disabled(model.isCreatingPassword)
        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("锁具动态").font(.headline)
            if model.events.isEmpty { Text("暂无记录").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 70) }
            else { ForEach(model.events.prefix(8)) { event in HStack(alignment: .top, spacing: 10) { Image(systemName: "lock.open").foregroundStyle(Color.openHomeLock); VStack(alignment: .leading, spacing: 2) { Text(event.content).font(.subheadline); Text(event.time).font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(.vertical, 5) } }
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.red) }
        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ label: String, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 5) { Image(systemName: symbol); Text(value).font(.headline); Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7)) }.frame(maxWidth: .infinity)
    }
}

private extension Color { static let openHomeLock = Color(red: 0.397, green: 0.438, blue: 0.333) }
