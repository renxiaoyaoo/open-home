import AVKit
import Observation
import SwiftUI
import UIKit

@MainActor @Observable final class LockViewModel {
    enum RecordKind: String, CaseIterable, Identifiable { case dynamics = "锁具动态", security = "告警", operation = "操作记录"; var id: Self { self } }
    var devices: [LockDevice] = []; var selectedDeviceID = ""; var detail: LockDetail?
    var dynamics: [LockEvent] = []; var security: [LockEvent] = []; var operations: [LockEvent] = []; var captures: [LockCapture] = []
    var cursors: [RecordKind: String] = [:]; var captureCursor: String?; var temporaryPassword: LockTemporaryPassword?
    var isLoading = false; var loadingMore: String?; var isCreatingPassword = false; var message: String?; var notice: String?
    private let provider: any LockProvider
    init(provider: any LockProvider) {
        self.provider = provider
        if let cached = ModuleContentStore.load("lock.json", as: LockCache.self) {
            devices = cached.devices; selectedDeviceID = cached.selectedDeviceID; detail = cached.detail
            dynamics = cached.dynamics; security = cached.security; operations = cached.operations; captures = cached.captures
        }
    }

    func discardDisplayedContent() {
        devices = []; selectedDeviceID = ""; detail = nil; dynamics = []; security = []; operations = []; captures = []; temporaryPassword = nil; message = nil; notice = nil
    }

    func load() async {
        let revision = ModuleContentStore.revision
        guard !ModuleContentStore.isBlocked("lock.json") else { discardDisplayedContent(); return }
        guard !isLoading else { return }; isLoading = true; defer { isLoading = false }
        do {
            if devices.isEmpty { devices = try await provider.devices(); selectedDeviceID = devices.first?.id ?? "" }
            guard revision == ModuleContentStore.revision, !ModuleContentStore.isBlocked("lock.json") else { discardDisplayedContent(); return }
            guard !selectedDeviceID.isEmpty else { throw ProviderError.invalidResponse }
            async let nextDetail = provider.detail(deviceID: selectedDeviceID)
            async let nextDynamics = provider.dynamics(deviceID: selectedDeviceID, cursor: nil)
            async let nextSecurity = provider.securityLogs(deviceID: selectedDeviceID, cursor: nil)
            async let nextOperations = provider.operationLogs(deviceID: selectedDeviceID, cursor: nil)
            async let nextCaptures = provider.captures(deviceID: selectedDeviceID, cursor: nil)
            let (loadedDetail, d, s, o, c) = try await (nextDetail, nextDynamics, nextSecurity, nextOperations, nextCaptures)
            guard revision == ModuleContentStore.revision, !ModuleContentStore.isBlocked("lock.json") else { discardDisplayedContent(); return }
            detail = loadedDetail; dynamics = d.items; security = s.items; operations = o.items; captures = c.items
            cursors = [.dynamics: d.nextCursor, .security: s.nextCursor, .operation: o.nextCursor].compactMapValues { $0 }
            captureCursor = c.nextCursor; message = nil
            ModuleContentStore.save("lock.json", LockCache(devices: devices, selectedDeviceID: selectedDeviceID, detail: loadedDetail, dynamics: d.items, security: s.items, operations: o.items, captures: c.items))
        } catch is CancellationError { return }
        catch let error as URLError where error.code == .cancelled { return }
        catch let error as APIError {
            if case .providerAuthenticationRequired = error { discardDisplayedContent() }
            message = error.localizedDescription
        }
        catch { message = error.localizedDescription }
    }
    func select(_ id: String) async { selectedDeviceID = id; detail = nil; dynamics = []; security = []; operations = []; captures = []; cursors = [:]; captureCursor = nil; temporaryPassword = nil; await load() }
    func loadMore(_ kind: RecordKind) async {
        guard let cursor = cursors[kind], loadingMore == nil else { return }; loadingMore = kind.rawValue; defer { loadingMore = nil }
        do {
            let page: LockPage<LockEvent>
            switch kind { case .dynamics: page = try await provider.dynamics(deviceID: selectedDeviceID, cursor: cursor); case .security: page = try await provider.securityLogs(deviceID: selectedDeviceID, cursor: cursor); case .operation: page = try await provider.operationLogs(deviceID: selectedDeviceID, cursor: cursor) }
            let existing = Set(records(kind).map(\.id)); let additions = page.items.filter { !existing.contains($0.id) }; setRecords(kind, records(kind) + additions); cursors[kind] = additions.isEmpty || page.nextCursor == cursor ? nil : page.nextCursor; message = nil
        } catch is CancellationError { return }
        catch let error as URLError where error.code == .cancelled { return }
        catch { message = error.localizedDescription }
    }
    func loadMoreCaptures() async {
        guard let cursor = captureCursor, loadingMore == nil else { return }; loadingMore = "captures"; defer { loadingMore = nil }
        do { let page = try await provider.captures(deviceID: selectedDeviceID, cursor: cursor); let existing = Set(captures.map(\.id)); let additions = page.items.filter { !existing.contains($0.id) }; captures += additions; captureCursor = additions.isEmpty || page.nextCursor == cursor ? nil : page.nextCursor; message = nil }
        catch is CancellationError { return }
        catch let error as URLError where error.code == .cancelled { return }
        catch { message = error.localizedDescription }
    }
    func records(_ kind: RecordKind) -> [LockEvent] { switch kind { case .dynamics: dynamics; case .security: security; case .operation: operations } }
    private func setRecords(_ kind: RecordKind, _ value: [LockEvent]) { switch kind { case .dynamics: dynamics = value; case .security: security = value; case .operation: operations = value } }
    func copy(_ password: String) {
        UIPasteboard.general.string = password
        notice = "密码已复制"
        Task { try? await Task.sleep(for: .seconds(2.2)); if notice == "密码已复制" { notice = nil } }
    }
    func createPassword() async {
        guard !selectedDeviceID.isEmpty, !isCreatingPassword else { return }; isCreatingPassword = true; defer { isCreatingPassword = false }
        do { let value = try await provider.createTemporaryPassword(deviceID: selectedDeviceID); temporaryPassword = value; copy(value.password) }
        catch is CancellationError { return }
        catch let error as URLError where error.code == .cancelled { return }
        catch { message = error.localizedDescription }
    }
}

struct LockView: View {
    private enum Page: String, CaseIterable, Identifiable { case security = "安防", captures = "抓拍相册"; var id: Self { self } }
    private enum Viewer: Identifiable { case image(URL), video(URL); var id: String { switch self { case .image(let url): "image:\(url)"; case .video(let url): "video:\(url)" } } }
    @Environment(AppModel.self) private var appModel
    @State private var model: LockViewModel; @State private var page = Page.security; @State private var recordKind = LockViewModel.RecordKind.dynamics; @State private var viewer: Viewer?
    init(provider: any LockProvider) { _model = State(initialValue: LockViewModel(provider: provider)) }
    var body: some View {
        Group {
            if let detail = model.detail {
                List {
                    Section {
                        infoRow("所连 Wi-Fi", wifiSummary(detail))
                        infoRow("信号", signalQuality(detail.wifiSignal), tone: statusTone(signalQuality(detail.wifiSignal)))
                        batteryRow("门锁电量", detail.battery)
                        batteryRow("猫眼电量", detail.cameraBattery)
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(detail.name ?? model.devices.first(where: { $0.id == model.selectedDeviceID })?.name ?? "智能门锁").font(.title3.weight(.semibold)).foregroundStyle(.primary).textCase(nil)
                            Spacer()
                            if model.devices.count > 1 {
                                Menu { ForEach(model.devices) { device in Button(device.name) { Task { await model.select(device.id) } } } } label: { Image(systemName: "chevron.up.chevron.down") }
                                    .accessibilityLabel("选择门锁")
                                    .textCase(nil)
                            }
                        }
                    }
                    if let value = model.temporaryPassword {
                        Section {
                            HStack(spacing: 12) {
                                Text("临时密码")
                                Spacer(minLength: 12)
                                Text(value.password).font(.system(size: 28, weight: .semibold, design: .monospaced)).foregroundStyle(.primary)
                                Button { model.copy(value.password) } label: {
                                    Image(systemName: "doc.on.doc").font(.title2.weight(.semibold))
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("复制密码")
                            }
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let remaining = max(0, Int(value.expiresAt.timeIntervalSince(context.date)))
                                infoRow("剩余", String(format: "%02d:%02d", remaining / 60, remaining % 60))
                            }
                        }
                    }
                    Section {
                        Button { Task { await model.createPassword() } } label: {
                            Group {
                                if model.temporaryPassword == nil { Label("查看密码", systemImage: "key") }
                                else { Text("重新生成") }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(model.isCreatingPassword)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    Section {
                        Picker("内容", selection: $page) { ForEach(Page.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        if page == .security {
                            Picker("记录", selection: $recordKind) { ForEach(LockViewModel.RecordKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                            let records = model.records(recordKind)
                            if records.isEmpty { Text("暂无记录").foregroundStyle(.secondary) }
                            ForEach(records) { event in eventRow(event) }
                            if model.cursors[recordKind] != nil { ProgressView().frame(maxWidth: .infinity).task(id: "\(recordKind.id)|\(model.cursors[recordKind] ?? "")") { await model.loadMore(recordKind) } }
                        } else {
                            if model.captures.isEmpty { Text("暂无抓拍").foregroundStyle(.secondary) }
                            else { captureGrid }
                            if model.captureCursor != nil { ProgressView().frame(maxWidth: .infinity).task(id: model.captureCursor) { await model.loadMoreCaptures() } }
                        }
                    }
                    if let message = model.message, !Self.isCancellation(message) { Section { Text(message).foregroundStyle(.red) } }
                }
                .listStyle(.insetGrouped)
            } else if model.isLoading { ProgressView("正在读取门锁").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { OpenHomeUnavailable(title: "还没有门锁内容", systemImage: "lock.shield", description: model.message ?? "连接恢复后可以重新读取。", actionTitle: "重试") { Task { await model.load() } } }
        }
        .overlay(alignment: .bottom) { if let notice = model.notice { Text(notice).font(.footnote.weight(.medium)).foregroundStyle(Color.green).padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 16) } }
        .onChange(of: appModel.sessionRevision) { _, _ in model.discardDisplayedContent() }
        .task { await model.load() }.refreshable { await model.load() }.sheet(item: $viewer) { MediaViewer(item: $0) }
    }
    private func infoRow(_ title: String, _ value: String, monospaced: Bool = false, tone: Color = .secondary) -> some View {
        LabeledContent(title) {
            Text(value).font(monospaced ? .body.monospaced() : .body).multilineTextAlignment(.trailing).foregroundStyle(tone)
        }
    }
    private func batteryRow(_ title: String, _ raw: String?) -> some View {
        let digits = raw?.filter(\.isNumber)
        let percent = digits.flatMap(Int.init)
        return HStack(spacing: 10) {
            Text(title)
            Spacer(minLength: 12)
            if let percent {
                Text("\(percent)%").foregroundStyle(batteryTone(raw))
                ProgressView(value: min(max(Double(percent), 0), 100), total: 100)
                    .tint(batteryTone(raw))
                    .frame(width: 56)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }
    private func wifiSummary(_ detail: LockDetail) -> String {
        let name = detail.wifiName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let network = name.flatMap { $0.isEmpty ? nil : $0 } ?? "未知"
        guard let updatedAt = detail.batteryUpdatedAt else { return network }
        return "\(network) · \(displayTime(updatedAt)) 更新"
    }
    private static func isCancellation(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text == "canceled" || text == "cancelled"
    }
    private func eventRow(_ event: LockEvent) -> some View {
        Button { if let image = event.image { viewer = .image(image) } } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.content).font(.body).foregroundStyle(.primary).lineLimit(2)
                    Text(displayTime(event.time)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let image = event.image { captureImage(image).frame(width: 64, height: 48).clipShape(RoundedRectangle(cornerRadius: 8)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(event.image == nil)
    }
    private var captureGrid: some View {
        VStack(spacing: 10) {
            if model.captures.isEmpty { ContentUnavailableView("暂无抓拍", systemImage: "photo", description: Text("近 7 天的照片和视频会出现在这里")).frame(minHeight: 160) }
            else { LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) { ForEach(model.captures) { capture in Button { viewer = capture.video.map(Viewer.video) ?? .image(capture.image) } label: { VStack(alignment: .leading, spacing: 5) { ZStack { captureImage(capture.image); if capture.video != nil { Image(systemName: "play.fill").font(.headline).foregroundStyle(.white).padding(9).background(.black.opacity(0.55), in: Circle()) } }.aspectRatio(4 / 3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10)); Text(capture.video == nil ? "照片" : "视频").font(.caption.bold()).foregroundStyle(.primary); Text(displayTime(capture.time)).font(.caption2).foregroundStyle(.secondary).lineLimit(1) } }.buttonStyle(.plain) } } }
            if let cursor = model.captureCursor { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8).task(id: cursor) { await model.loadMoreCaptures() } }
        }
    }
    private func captureImage(_ url: URL) -> some View { RotatedCaptureImage(url: url) }
    private func displayTime(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未知" }
        guard let date = openHomeDate(trimmed) else { return trimmed }
        return openHomeTimeText(date)
    }
    private func metric(_ label: String, _ value: String, _ symbol: String) -> some View { VStack(spacing: 5) { Image(systemName: symbol); Text(value).font(.headline); Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7)) }.frame(maxWidth: .infinity) }
    private func signalQuality(_ value: String?) -> String {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return "未知" }
        if raw.contains("优") || raw.contains("强") || raw.contains("好") || raw.lowercased().contains("good") { return "良好" }
        if raw.contains("中") || raw.contains("一般") || raw.lowercased().contains("fair") { return "一般" }
        if raw.contains("差") || raw.contains("弱") || raw.lowercased().contains("poor") { return "较弱" }
        let number = Double(raw.filter { $0.isNumber || $0 == "-" || $0 == "." })
        guard let number else { return "未知" }
        if number < 0 { return number >= -60 ? "良好" : number >= -75 ? "一般" : "较弱" }
        return number >= 70 ? "良好" : number >= 40 ? "一般" : "较弱"
    }

    private struct MediaViewer: View {
        let item: Viewer; @Environment(\.dismiss) private var dismiss
        var body: some View { NavigationStack { Group { switch item { case .image(let url): RotatedCaptureImage(url: url).padding(); case .video(let url): RotatedVideo(url: url) } }.background(.black).navigationTitle("抓拍").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } } } }
    }
}

private struct RotatedCaptureImage: View {
    let url: URL
    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                        .frame(width: proxy.size.height, height: proxy.size.width)
                        .rotationEffect(.degrees(90))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else if case .failure = phase {
                    Color.black.opacity(0.08).overlay { Image(systemName: "photo") }
                } else {
                    Color.black.opacity(0.06).overlay { ProgressView() }
                }
            }
        }.clipped()
    }
}

private struct RotatedVideo: View {
    let url: URL
    var body: some View {
        GeometryReader { proxy in
            VideoPlayer(player: AVPlayer(url: url))
                .frame(width: proxy.size.height, height: proxy.size.width)
                .rotationEffect(.degrees(90))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
    }
}

private struct LockCache: Codable {
    var devices: [LockDevice]
    var selectedDeviceID: String
    var detail: LockDetail
    var dynamics: [LockEvent]
    var security: [LockEvent]
    var operations: [LockEvent]
    var captures: [LockCapture]
}

private extension Color { static let openHomeLock = Color(red: 0.397, green: 0.438, blue: 0.333) }
