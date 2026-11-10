import Observation
import SwiftUI

@MainActor
@Observable
final class VehicleViewModel {
    var snapshot: VehicleSnapshot?
    var isLoading = false
    var message: String?
    private let provider: any HomeProvider<VehicleSnapshot>
    private let liveStatus: LiveStatusManager
    private var activityID: String?

    var refreshInterval: Duration {
        switch snapshot?.state {
        case .ready, .driving, .charging: return .seconds(5)
        default: return .seconds(30)
        }
    }

    init(provider: any HomeProvider<VehicleSnapshot>, registrar: (any LiveActivityRegistrar)? = nil) { self.provider = provider; liveStatus = LiveStatusManager(registrar: registrar) }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do { let value = try await provider.snapshot(); snapshot = value; message = nil; await updateLiveStatus(value) }
        catch { message = error is URLError ? "无法连接 OpenHome" : error.localizedDescription }
    }

    private func updateLiveStatus(_ value: VehicleSnapshot) async {
        let active = value.state == .ready || value.state == .driving || value.state == .charging
        let end = value.remainingChargeMinutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        let detail = value.state == .charging ? value.batteryPercent.map { "电量 \(Int($0))%" } : value.speedKPH.map { "时速 \(Int($0)) km/h" }
        let state = OpenHomeStatusAttributes.ContentState(title: value.name, state: value.state.label, detail: detail, progress: value.state == .charging ? value.batteryPercent.map { $0 / 100 } : nil, expectedEnd: end)
        if active, let activityID { await liveStatus.update(activityID: activityID, state: state) }
        else if active { activityID = try? await liveStatus.start(attributes: .init(provider: .auto, resourceID: value.vehicleID, resourceName: value.name), state: state) }
        else if let activityID { await liveStatus.end(activityID: activityID, state: state); self.activityID = nil }
    }
}

struct VehicleView: View {
    @State private var model: VehicleViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(provider: any HomeProvider<VehicleSnapshot>, registrar: (any LiveActivityRegistrar)? = nil) { _model = State(initialValue: VehicleViewModel(provider: provider, registrar: registrar)) }

    var body: some View {
        ScrollView {
            if let value = model.snapshot { dashboard(value).padding(14).frame(maxWidth: 520) }
            else if model.isLoading { ProgressView().padding(.top, 100) }
            else { ContentUnavailableView("车辆暂时未加载", systemImage: "car.side", description: Text(model.message ?? "下拉重试")) }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: model.refreshInterval)
            }
        }
        .refreshable { await model.refresh() }
    }

    private func dashboard(_ value: VehicleSnapshot) -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { VStack(alignment: .leading, spacing: 3) { Text(value.name).font(.title3.bold()); Text(value.state.label).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: value.state == .charging ? "bolt.car" : "car.side").font(.title2) }
                HStack(alignment: .lastTextBaseline) { Text(number(value.totalRangeKM)).font(.system(size: 42, weight: .medium, design: .rounded)); Text("km").font(.caption).foregroundStyle(.secondary); Spacer(); level("bolt.fill", value.batteryPercent, value.electricRangeKM, .green); level("fuelpump.fill", value.fuelPercent, value.fuelRangeKM, .blue) }
                HStack(spacing: 8) { Label(value.state.label, systemImage: "gauge.with.dots.needle.33percent"); if let location = value.locationName { Spacer(); Label(location, systemImage: "location.fill").lineLimit(1) } }.font(.caption).foregroundStyle(.secondary)
            }.padding(18).background(Color.openHomeAuto.opacity(0.13), in: RoundedRectangle(cornerRadius: 18))
            HStack(spacing: 10) { metric("总里程", value.odometerKM.map { "\(number($0)) km" } ?? "—", "road.lanes"); metric("车内温度", value.cabinTemperatureC.map { "\(number($0))℃" } ?? "—", "thermometer.medium") }
            if value.state == .charging { HStack { Label("正在充电", systemImage: "bolt.fill"); Spacer(); if let power = value.chargingPowerKW { Text("\(number(power)) kW") }; if let minutes = value.remainingChargeMinutes { Text("\(minutes / 60)h \(minutes % 60)m") } }.font(.subheadline.weight(.semibold)).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
        }
    }

    private func level(_ symbol: String, _ percent: Double?, _ range: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) { HStack(spacing: 4) { Image(systemName: symbol).foregroundStyle(color); Text(percent.map { "\(Int($0))%" } ?? "—").font(.subheadline.bold()) }; Text(range.map { "\(number($0)) km" } ?? "—").font(.caption2).foregroundStyle(.secondary) }.frame(width: 66, alignment: .leading)
    }
    private func metric(_ label: String, _ value: String, _ symbol: String) -> some View { HStack(spacing: 10) { Image(systemName: symbol).frame(width: 34, height: 34).background(Color.openHomeAuto.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading, spacing: 2) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline) } }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
    private func number(_ value: Double?) -> String { guard let value else { return "—" }; return value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1))) }
}

private extension VehicleSnapshot.State { var label: String { switch self { case .parked: "已熄火"; case .ready: "已启动"; case .driving: "行驶中"; case .charging: "充电中"; case .fault: "车辆异常" } } }
private extension Color { static let openHomeAuto = Color(red: 0.435, green: 0.396, blue: 0.349) }
