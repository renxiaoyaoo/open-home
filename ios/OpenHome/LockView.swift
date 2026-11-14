import AVKit
import Observation
import SwiftUI
import UIKit

@MainActor @Observable final class LockViewModel {
    enum RecordKind: String, CaseIterable, Identifiable { case dynamics = "锁具动态", security = "告警", operation = "操作记录"; var id: Self { self } }
    var devices: [LockDevice] = []; var selectedDeviceID = ""; var detail: LockDetail?
    var dynamics: [LockEvent] = []; var security: [LockEvent] = []; var operations: [LockEvent] = []; var captures: [LockCapture] = []
    var cursors: [RecordKind: String] = [:]; var captureCursor: String?; var temporaryPassword: LockTemporaryPassword?
    var isLoading = false; var loadingMore: String?; var isCreatingPassword = false; var message: String?
    private let provider: any LockProvider
    init(provider: any LockProvider) { self.provider = provider }

    func load() async {
        guard !isLoading else { return }; isLoading = true; defer { isLoading = false }
        do {
            if devices.isEmpty { devices = try await provider.devices(); selectedDeviceID = devices.first?.id ?? "" }
            guard !selectedDeviceID.isEmpty else { throw ProviderError.invalidResponse }
            async let nextDetail = provider.detail(deviceID: selectedDeviceID)
            async let nextDynamics = provider.dynamics(deviceID: selectedDeviceID, cursor: nil)
            async let nextSecurity = provider.securityLogs(deviceID: selectedDeviceID, cursor: nil)
            async let nextOperations = provider.operationLogs(deviceID: selectedDeviceID, cursor: nil)
            async let nextCaptures = provider.captures(deviceID: selectedDeviceID, cursor: nil)
            let (loadedDetail, d, s, o, c) = try await (nextDetail, nextDynamics, nextSecurity, nextOperations, nextCaptures)
            detail = loadedDetail; dynamics = d.items; security = s.items; operations = o.items; captures = c.items
            cursors = [.dynamics: d.nextCursor, .security: s.nextCursor, .operation: o.nextCursor].compactMapValues { $0 }
            captureCursor = c.nextCursor; message = nil
        } catch { message = error.localizedDescription }
    }
    func select(_ id: String) async { selectedDeviceID = id; detail = nil; dynamics = []; security = []; operations = []; captures = []; cursors = [:]; captureCursor = nil; temporaryPassword = nil; await load() }
    func loadMore(_ kind: RecordKind) async {
        guard let cursor = cursors[kind], loadingMore == nil else { return }; loadingMore = kind.rawValue; defer { loadingMore = nil }
        do {
            let page: LockPage<LockEvent>
            switch kind { case .dynamics: page = try await provider.dynamics(deviceID: selectedDeviceID, cursor: cursor); case .security: page = try await provider.securityLogs(deviceID: selectedDeviceID, cursor: cursor); case .operation: page = try await provider.operationLogs(deviceID: selectedDeviceID, cursor: cursor) }
            let existing = Set(records(kind).map(\.id)); let additions = page.items.filter { !existing.contains($0.id) }; setRecords(kind, records(kind) + additions); cursors[kind] = additions.isEmpty || page.nextCursor == cursor ? nil : page.nextCursor; message = nil
        } catch { message = error.localizedDescription }
    }
    func loadMoreCaptures() async {
        guard let cursor = captureCursor, loadingMore == nil else { return }; loadingMore = "captures"; defer { loadingMore = nil }
        do { let page = try await provider.captures(deviceID: selectedDeviceID, cursor: cursor); let existing = Set(captures.map(\.id)); let additions = page.items.filter { !existing.contains($0.id) }; captures += additions; captureCursor = additions.isEmpty || page.nextCursor == cursor ? nil : page.nextCursor; message = nil }
        catch { message = error.localizedDescription }
    }
    func records(_ kind: RecordKind) -> [LockEvent] { switch kind { case .dynamics: dynamics; case .security: security; case .operation: operations } }
    private func setRecords(_ kind: RecordKind, _ value: [LockEvent]) { switch kind { case .dynamics: dynamics = value; case .security: security = value; case .operation: operations = value } }
    func createPassword() async {
        guard !selectedDeviceID.isEmpty, !isCreatingPassword else { return }; isCreatingPassword = true; defer { isCreatingPassword = false }
        do { let value = try await provider.createTemporaryPassword(deviceID: selectedDeviceID); temporaryPassword = value; UIPasteboard.general.string = value.password; message = nil }
        catch { message = error.localizedDescription }
    }
}

struct LockView: View {
    private enum Page: String, CaseIterable, Identifiable { case security = "安防", captures = "抓拍相册"; var id: Self { self } }
    private enum Viewer: Identifiable { case image(URL), video(URL); var id: String { switch self { case .image(let url): "image:\(url)"; case .video(let url): "video:\(url)" } } }
    @State private var model: LockViewModel; @State private var page = Page.security; @State private var recordKind = LockViewModel.RecordKind.dynamics; @State private var viewer: Viewer?
    init(provider: any LockProvider) { _model = State(initialValue: LockViewModel(provider: provider)) }
    var body: some View {
        ScrollView {
            if let detail = model.detail { VStack(spacing: 12) { status(detail); passwordCard; recordsCard }.padding(14).frame(maxWidth: 520) }
            else if model.isLoading { ProgressView().padding(.top, 100) }
            else { ContentUnavailableView("门锁暂时未加载", systemImage: "lock.shield", description: Text(model.message ?? "下拉重试")) }
        }.task { await model.load() }.refreshable { await model.load() }.sheet(item: $viewer) { MediaViewer(item: $0) }
    }
    private func status(_ detail: LockDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text(detail.name ?? model.devices.first(where: { $0.id == model.selectedDeviceID })?.name ?? "智能门锁").font(.title3.bold()); Text(detail.wifiName ?? "Wi‑Fi").font(.caption).foregroundStyle(.white.opacity(0.7)) }; Spacer(); if model.devices.count > 1 { Menu { ForEach(model.devices) { device in Button(device.name) { Task { await model.select(device.id) } } } } label: { Image(systemName: "chevron.up.chevron.down") } } }
            HStack(spacing: 10) { metric("门锁", detail.battery.map { "\($0)%" } ?? "—", "battery.75percent"); metric("猫眼", detail.cameraBattery.map { "\($0)%" } ?? "—", "camera"); metric("信号", detail.wifiSignal ?? "—", "wifi") }
        }.padding(18).foregroundStyle(.white).background(Color.openHomeLock, in: RoundedRectangle(cornerRadius: 18))
    }
    private var passwordCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill").frame(width: 42, height: 42).background(Color.openHomeLock.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) { Text("一次性临时密码").font(.caption).foregroundStyle(.secondary); if let value = model.temporaryPassword { Text(value.password).font(.system(.title3, design: .monospaced, weight: .semibold)).tracking(2); Text("有效至 \(value.expiresAt.formatted(date: .omitted, time: .shortened)) · 已复制").font(.caption2).foregroundStyle(.secondary) } else { Text("30 分钟内有效").font(.subheadline.weight(.medium)) } }
            Spacer(); Button(model.temporaryPassword == nil ? "查看密码" : "重新生成") { Task { await model.createPassword() } }.buttonStyle(.borderedProminent).tint(.openHomeLock).disabled(model.isCreatingPassword)
        }.frame(minHeight: 76).padding(16).background(Color.openHomeSurface, in: RoundedRectangle(cornerRadius: 16))
    }
    private var recordsCard: some View {
        VStack(spacing: 12) { Picker("内容", selection: $page) { ForEach(Page.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented); if page == .security { securityRecords } else { captureGrid }; if let message = model.message { Text(message).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) } }
            .padding(16).background(Color.openHomeSurface, in: RoundedRectangle(cornerRadius: 16))
    }
    private var securityRecords: some View {
        VStack(spacing: 10) {
            Picker("记录", selection: $recordKind) { ForEach(LockViewModel.RecordKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            let records = model.records(recordKind)
            if records.isEmpty { Text("暂无记录").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 90) } else { ForEach(records) { event in eventRow(event) } }
            if let cursor = model.cursors[recordKind] { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8).task(id: "\(recordKind.id)|\(cursor)") { await model.loadMore(recordKind) } }
        }
    }
    private func eventRow(_ event: LockEvent) -> some View {
        Button { if let image = event.image { viewer = .image(image) } } label: { HStack(alignment: .top, spacing: 10) { VStack(alignment: .leading, spacing: 2) { Text(event.content).font(.subheadline).foregroundStyle(.primary); Text(displayTime(event.time)).font(.caption).foregroundStyle(.secondary) }; Spacer(); if let image = event.image { captureImage(image).frame(width: 60, height: 46).clipShape(RoundedRectangle(cornerRadius: 8)) } }.padding(.vertical, 5) }.buttonStyle(.plain).disabled(event.image == nil)
    }
    private var captureGrid: some View {
        VStack(spacing: 10) {
            if model.captures.isEmpty { Text("暂无抓拍").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 90) }
            else { LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) { ForEach(model.captures) { capture in Button { viewer = capture.video.map(Viewer.video) ?? .image(capture.image) } label: { VStack(alignment: .leading, spacing: 5) { ZStack { captureImage(capture.image); if capture.video != nil { Image(systemName: "play.fill").font(.headline).foregroundStyle(.white).padding(9).background(.black.opacity(0.55), in: Circle()) } }.aspectRatio(4 / 3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10)); Text(displayTime(capture.time)).font(.caption2).foregroundStyle(.secondary).lineLimit(1) } }.buttonStyle(.plain) } } }
            if let cursor = model.captureCursor { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8).task(id: cursor) { await model.loadMoreCaptures() } }
        }
    }
    private func captureImage(_ url: URL) -> some View { AsyncImage(url: url) { phase in if case .success(let image) = phase { image.resizable().scaledToFill().rotationEffect(.degrees(90)).scaleEffect(1.34) } else if case .failure = phase { Color.black.opacity(0.08).overlay { Image(systemName: "photo") } } else { Color.black.opacity(0.06).overlay { ProgressView() } } }.clipped() }
    private func displayTime(_ value: String) -> String {
        let date: Date?
        if let seconds = Double(value), seconds > 1_000_000_000 { date = Date(timeIntervalSince1970: seconds) }
        else { let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
        guard let date else { return value }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
    private func metric(_ label: String, _ value: String, _ symbol: String) -> some View { VStack(spacing: 5) { Image(systemName: symbol); Text(value).font(.headline); Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7)) }.frame(maxWidth: .infinity) }

    private struct MediaViewer: View {
        let item: Viewer; @Environment(\.dismiss) private var dismiss
        var body: some View { NavigationStack { Group { switch item { case .image(let url): AsyncImage(url: url) { image in image.resizable().scaledToFit().rotationEffect(.degrees(90)) } placeholder: { ProgressView() }; case .video(let url): VideoPlayer(player: AVPlayer(url: url)) } }.background(.black).navigationTitle("抓拍").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } } } }
    }
}

private extension Color { static let openHomeLock = Color(red: 0.397, green: 0.438, blue: 0.333) }
