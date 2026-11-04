import Observation
import SwiftUI

@MainActor
@Observable
final class DryerViewModel {
    var snapshot: DryerSnapshot?
    var isLoading = false
    var message: String?
    private let provider: any HomeProvider<DryerSnapshot>
    private let liveStatus = LiveStatusManager()
    private var activityID: String?

    init(provider: any HomeProvider<DryerSnapshot>) { self.provider = provider }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do { let value = try await provider.snapshot(); snapshot = value; message = nil; await updateLiveStatus(value) }
        catch { message = error is URLError ? "无法连接 OpenHome" : error.localizedDescription }
    }

    private func updateLiveStatus(_ value: DryerSnapshot) async {
        let active = value.state == .running || value.state == .scheduled || value.state == .paused
        let state = OpenHomeStatusAttributes.ContentState(title: value.name, state: value.state.label, detail: value.programName, progress: nil, expectedEnd: value.expectedFinish)
        if active, let activityID { await liveStatus.update(activityID: activityID, state: state) }
        else if active {
            activityID = try? await liveStatus.start(attributes: .init(provider: .living, resourceID: value.deviceID, resourceName: value.name), state: state)
        } else if let activityID { await liveStatus.end(activityID: activityID, state: state); self.activityID = nil }
    }
}

struct DryerView: View {
    @State private var model: DryerViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(provider: any HomeProvider<DryerSnapshot>) { _model = State(initialValue: DryerViewModel(provider: provider)) }

    var body: some View {
        ScrollView {
            if let value = model.snapshot {
                VStack(spacing: 12) {
                    statusCard(value)
                    HStack(spacing: 10) {
                        metric("程序", value.programName ?? "未选择", "washer")
                        metric("预计完成", value.expectedFinish?.formatted(date: .omitted, time: .shortened) ?? "—", "clock")
                    }
                }.padding(14).frame(maxWidth: 520)
            } else if model.isLoading { ProgressView().padding(.top, 100) }
            else { ContentUnavailableView("设备暂时未加载", systemImage: "washer", description: Text(model.message ?? "下拉重试")) }
        }
        .task { await model.refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(10)); await model.refresh() }
        }
        .refreshable { await model.refresh() }
    }

    private func statusCard(_ value: DryerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text(value.name).font(.title3.bold()); Text(value.state.label).font(.subheadline).foregroundStyle(.white.opacity(0.72)) }; Spacer(); Image(systemName: model.isLoading ? "arrow.triangle.2.circlepath" : "washer").font(.title2) }
            HStack(alignment: .lastTextBaseline) { VStack(alignment: .leading, spacing: 4) { Text("当前状态").font(.caption).foregroundStyle(.white.opacity(0.65)); Text(value.state.label).font(.system(size: 30, weight: .semibold)) }; Spacer(); VStack(alignment: .trailing, spacing: 4) { Text("剩余时间").font(.caption).foregroundStyle(.white.opacity(0.65)); Text(clock(value.remainingMinutes)).font(.system(size: 34, weight: .semibold, design: .monospaced)) } }
        }.padding(20).foregroundStyle(.white).background(Color.openHomeLiving, in: RoundedRectangle(cornerRadius: 18))
    }

    private func metric(_ label: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) { Image(systemName: symbol).frame(width: 34, height: 34).background(Color.openHomeLiving.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading, spacing: 2) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline).lineLimit(1) } }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func clock(_ minutes: Int?) -> String { let value = max(0, minutes ?? 0); return String(format: "%02d:%02d", value / 60, value % 60) }
}

private extension DryerSnapshot.State {
    var label: String { switch self { case .off: "已关机"; case .idle: "待机"; case .running: "烘干中"; case .paused: "已暂停"; case .scheduled: "已预约"; case .finished: "已完成"; case .fault: "设备故障" } }
}

private extension Color { static let openHomeLiving = Color(red: 0.286, green: 0.420, blue: 0.443) }
