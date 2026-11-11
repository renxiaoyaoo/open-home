import Charts
import Observation
import SwiftUI

@MainActor @Observable final class VehicleViewModel {
    var snapshot: VehicleSnapshot?; var energy: VehicleEnergy?; var isLoading = false; var message: String?
    private let provider: any VehicleProvider; private let liveStatus: LiveStatusManager; private var activityID: String?
    var refreshInterval: Duration { switch snapshot?.state { case .ready, .driving, .charging: .seconds(5); default: .seconds(30) } }
    init(provider: any VehicleProvider, registrar: (any LiveActivityRegistrar)? = nil) { self.provider = provider; liveStatus = LiveStatusManager(registrar: registrar) }
    func loadDetail() async {
        guard !isLoading else { return }; isLoading = true; defer { isLoading = false }
        do { let value = try await provider.detail(); snapshot = value.summary; energy = value.energy; message = nil; await updateLiveStatus(value.summary) }
        catch { message = error is URLError ? "无法连接 OpenHome" : error.localizedDescription }
    }
    func refreshStatus() async {
        guard !isLoading else { return }
        do { let value = try await provider.snapshot(); snapshot = value; message = nil; await updateLiveStatus(value) }
        catch { message = error is URLError ? "无法连接 OpenHome" : error.localizedDescription }
    }
    private func updateLiveStatus(_ value: VehicleSnapshot) async {
        let active = value.state == .ready || value.state == .driving || value.state == .charging
        let end = value.remainingChargeMinutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        let detail = value.state == .charging ? value.batteryPercent.map { "电量 \(Int($0))%" } : value.speedKPH.map { "时速 \(Int($0)) km/h" }
        let state = OpenHomeStatusAttributes.ContentState(title: value.name, state: value.state.label, detail: detail, progress: value.state == .charging ? value.batteryPercent.map { $0 / 100 } : nil, expectedEnd: end)
        if active, let activityID, await liveStatus.update(activityID: activityID, state: state) { return }
        else if active { activityID = try? await liveStatus.start(attributes: .init(provider: .auto, resourceID: value.vehicleID, resourceName: value.name), state: state) }
        else if let activityID { await liveStatus.end(activityID: activityID, state: state); self.activityID = nil }
    }
}

struct VehicleView: View {
    @State private var model: VehicleViewModel; @Environment(\.scenePhase) private var scenePhase
    init(provider: any VehicleProvider, registrar: (any LiveActivityRegistrar)? = nil) { _model = State(initialValue: VehicleViewModel(provider: provider, registrar: registrar)) }
    var body: some View {
        ScrollView {
            if let value = model.snapshot { dashboard(value).padding(14).frame(maxWidth: 520) }
            else if model.isLoading { ProgressView().padding(.top, 100) }
            else { ContentUnavailableView("车辆暂时未加载", systemImage: "car.side", description: Text(model.message ?? "下拉重试")) }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if model.energy == nil { await model.loadDetail() }
            while !Task.isCancelled { try? await Task.sleep(for: model.refreshInterval); await model.refreshStatus() }
        }
        .refreshable { await model.loadDetail() }
    }

    private func dashboard(_ value: VehicleSnapshot) -> some View {
        VStack(spacing: 12) {
            summaryCard(value)
            mileageGrid(value)
            vehicleStateCard(value)
            if let energy = model.energy { energyCard(energy) }
            if value.state == .charging { chargingCard(value) }
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.red) }
        }
    }
    private func summaryCard(_ value: VehicleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text(cleanName(value.name)).font(.title3.bold()); Text(value.state.label).font(.caption).foregroundStyle(.secondary) }; Spacer(); connection(value) }
            HStack(alignment: .lastTextBaseline) { Text(number(value.totalRangeKM)).font(.system(size: 42, weight: .medium, design: .rounded)); Text("km").font(.caption).foregroundStyle(.secondary); Spacer(); level("bolt.fill", value.batteryPercent, value.electricRangeKM, .green); level("fuelpump.fill", value.fuelPercent, value.fuelRangeKM, .blue) }
            HStack(spacing: 8) { Label(value.driveMode == "electric" ? "EV" : value.driveMode == "hybrid" ? "HEV" : value.state.label, systemImage: "gauge.with.dots.needle.33percent"); if let location = value.locationName { Spacer(); Label(location, systemImage: "location.fill").lineLimit(1) } }.font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(Color.openHomeAuto.opacity(0.13), in: RoundedRectangle(cornerRadius: 18))
    }
    private func mileageGrid(_ value: VehicleSnapshot) -> some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
            metric("总里程", value.odometerKM, "公里", "road.lanes"); metric("EV 里程", value.evMileageKM, "公里", "bolt.fill"); metric("HEV 里程", value.hevMileageKM, "公里", "fuelpump.fill"); metric("车内温度", value.cabinTemperatureC, "℃", "thermometer.medium")
        }
    }
    private func vehicleStateCard(_ value: VehicleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("车辆状态").font(.headline)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
                stateItem("车门", doorStatus(value)); stateItem("车窗", opening(value.windowsOpen)); stateItem("前舱盖", openLabel(value.hoodOpen)); stateItem("后备箱", openLabel(value.trunkOpen))
            }
            if let tire = value.tirePressureKPA { tirePanel(tire) }
            Divider()
            Text("整车状态").font(.subheadline.bold())
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
                stateItem("防盗状态", security(value.securityState)); stateItem("动力模式", driveMode(value.driveMode)); stateItem("OK 指示灯", value.okIndicator.map { $0 ? "点亮" : "熄灭" } ?? "—"); stateItem("行驶状态", value.state.label); stateItem("车速", unit(value.speedKPH, "公里/小时")); stateItem("功率", unit(value.powerOutputKW, "千瓦")); stateItem("冷却液温度", unit(value.engineCoolantC, "℃"))
            }
            if let health = value.health { healthPanel(health) }
        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
    private func healthPanel(_ health: [String: String]) -> some View {
        let items = [("发动机", "engine"), ("制动系统", "braking"), ("ABS 系统", "abs"), ("SRS 系统", "srs"), ("胎压监测系统", "tirePressure"), ("电子车身稳定系统", "stability"), ("转向系统", "steering"), ("发动机冷却液温度", "coolant"), ("机油压力", "oilPressure"), ("低压供电系统", "lowVoltage"), ("动力电池", "tractionBattery"), ("动力系统", "powertrain")]
        return VStack(spacing: 0) {
            HStack { Text("健康检测").font(.subheadline.bold()); Spacer(); Text(health.values.contains("warning") ? "发现异常" : "正常").font(.caption.bold()).foregroundStyle(health.values.contains("warning") ? .red : .green) }.padding(.vertical, 8)
            ForEach(items, id: \.1) { label, key in HStack { Text(label).font(.caption); Spacer(); Text(healthLabel(health[key])).font(.caption.bold()).foregroundStyle(health[key] == "warning" ? .red : .green) }.padding(.vertical, 7); Divider() }
        }
    }
    private func energyCard(_ value: VehicleEnergy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("能耗").font(.headline); Spacer(); if let rank = value.rankPercent { Text("近 \(number(value.recentDistanceKm)) 公里领先 \(number(rank))%").font(.caption).foregroundStyle(.secondary) } }
            HStack(spacing: 8) { energyMetric("平均行车能耗", value.equivalentFuelLitresPer100Km, "L/100km", "gauge.with.dots.needle.67percent"); energyMetric("累计平均能耗", value.cumulativeEquivalentFuelLitresPer100Km, "L/100km", "chart.line.uptrend.xyaxis") }
            if value.electricityKwhPer100Km != nil || value.fuelLitresPer100Km != nil { equation("近期", value.equivalentFuelLitresPer100Km, value.electricityKwhPer100Km, value.fuelLitresPer100Km) }
            if value.cumulativeElectricityKwhPer100Km != nil || value.cumulativeFuelLitresPer100Km != nil { equation("累计", value.cumulativeEquivalentFuelLitresPer100Km, value.cumulativeElectricityKwhPer100Km, value.cumulativeFuelLitresPer100Km) }
            if let rank = value.cumulativeRankPercent { Label("累计能耗领先 \(number(rank))%", systemImage: "chart.line.uptrend.xyaxis").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 8) { energyMetric("电耗", value.electricityKwh, "kWh", "bolt.fill"); energyMetric("油耗", value.fuelLitres, "L", "fuelpump.fill"); energyMetric("费用", value.costYuan, "元", "yensign.circle") }
            if let breakdown = value.breakdown { breakdownChart(breakdown) }
            if !value.recentTrend.isEmpty { trendChart(value.recentTrend) }
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) { energyMetric("累计里程", value.totalDistanceKm, "公里", "road.lanes"); energyMetric("每公里费用", value.costPerKmYuan, "元", "banknote") }
        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
    private func equation(_ label: String, _ equivalent: Double?, _ electricity: Double?, _ fuel: Double?) -> some View {
        HStack(spacing: 6) { Text(label).foregroundStyle(.secondary); Label("\(number(electricity)) kWh", systemImage: "bolt.fill").foregroundStyle(.green); Text("+"); Label("\(number(fuel)) L", systemImage: "fuelpump.fill").foregroundStyle(.blue); Spacer(); Text("≈ \(number(equivalent)) L/100km").bold() }.font(.caption).padding(12).background(Color.openHomeBackground, in: RoundedRectangle(cornerRadius: 12))
    }
    private func breakdownChart(_ value: VehicleEnergyBreakdown) -> some View {
        let parts = [("驱动", value.propulsionPercent, Color.brown), ("空调", value.climatePercent, .teal), ("电器", value.electricalPercent, .orange), ("其他", value.otherPercent, .gray)]
        return VStack(alignment: .leading, spacing: 8) { Text("能耗分布").font(.subheadline.bold()); GeometryReader { geometry in HStack(spacing: 2) { ForEach(parts, id: \.0) { _, percent, color in if let percent, percent > 0 { color.frame(width: max(3, geometry.size.width * percent / 100)) } } } }.frame(height: 10).clipShape(Capsule()); HStack { ForEach(parts, id: \.0) { label, percent, color in if let percent { Label("\(label) \(number(percent))%", systemImage: "circle.fill").foregroundStyle(color).font(.caption2) } } } }
    }
    private func trendChart(_ points: [VehicleEnergyTrendPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text("近期能耗").font(.subheadline.bold()); Chart(points) { point in if let value = point.equivalentFuelLitresPer100Km { LineMark(x: .value("日期", point.date), y: .value("能耗", value)).foregroundStyle(Color.openHomeAuto).symbol(.circle) }; if let peer = point.peerAverageLitresPer100Km { LineMark(x: .value("日期", point.date), y: .value("同车型", peer)).foregroundStyle(.secondary).lineStyle(.init(dash: [4, 3])) } }.frame(height: 150).chartYAxis { AxisMarks(position: .leading) } }
    }
    private func chargingCard(_ value: VehicleSnapshot) -> some View { HStack { Label("正在充电", systemImage: "bolt.fill"); Spacer(); if let power = value.chargingPowerKW { Text("\(number(power)) kW") }; if let minutes = value.remainingChargeMinutes { Text("\(minutes / 60)h \(minutes % 60)m") } }.font(.subheadline.weight(.semibold)).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16)) }

    private func connection(_ value: VehicleSnapshot) -> some View { Image(systemName: value.online == false ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right").foregroundStyle(.secondary).accessibilityLabel(value.online == false ? "离线" : "在线") }
    private func level(_ symbol: String, _ percent: Double?, _ range: Double?, _ color: Color) -> some View { VStack(alignment: .leading, spacing: 4) { HStack(spacing: 4) { Image(systemName: symbol).foregroundStyle(color); Text(percent.map { "\(Int($0))%" } ?? "—").font(.subheadline.bold()) }; Text(range.map { "\(number($0)) km" } ?? "—").font(.caption2).foregroundStyle(.secondary) }.frame(width: 66, alignment: .leading) }
    private func metric(_ label: String, _ value: Double?, _ unit: String, _ symbol: String) -> some View { HStack(spacing: 10) { Image(systemName: symbol).frame(width: 34, height: 34).background(Color.openHomeAuto.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading, spacing: 2) { Text(label).font(.caption).foregroundStyle(.secondary); Text("\(number(value)) \(unit)").font(.headline) } }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
    private func energyMetric(_ label: String, _ value: Double?, _ unit: String, _ symbol: String) -> some View { VStack(alignment: .leading, spacing: 5) { Label(label, systemImage: symbol).font(.caption).foregroundStyle(.secondary); Text("\(number(value)) \(unit)").font(.subheadline.bold()) }.frame(maxWidth: .infinity, alignment: .leading).padding(11).background(Color.openHomeBackground, in: RoundedRectangle(cornerRadius: 12)) }
    private func stateItem(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(label).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption.bold()) }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(value.contains("打开") || value.contains("未锁") ? Color.orange.opacity(0.12) : Color.openHomeBackground, in: RoundedRectangle(cornerRadius: 11)) }
    private func tirePanel(_ value: VehicleTirePressure) -> some View { VStack(alignment: .leading, spacing: 8) { Text("胎压").font(.subheadline.bold()); HStack { tire("左前", value.frontLeft); tire("右前", value.frontRight); tire("左后", value.rearLeft); tire("右后", value.rearRight) } }.padding(12).background(Color.openHomeBackground, in: RoundedRectangle(cornerRadius: 12)) }
    private func tire(_ label: String, _ value: Double?) -> some View { VStack { Text(number(value)).font(.caption.bold()); Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
    private func doorStatus(_ value: VehicleSnapshot) -> String { if any(value.doorsOpen) { return "有打开" }; if any(value.doorsUnlocked) { return "已关未锁" }; return value.doorsOpen == nil && value.doorsUnlocked == nil ? "状态未知" : "已关已锁" }
    private func opening(_ value: VehicleCornerState?) -> String { value == nil ? "状态未知" : any(value) ? "有打开" : "已关" }
    private func any(_ value: VehicleCornerState?) -> Bool { [value?.frontLeft, value?.frontRight, value?.rearLeft, value?.rearRight].contains(true) }
    private func openLabel(_ value: Bool?) -> String { value == nil ? "状态未知" : value == true ? "已打开" : "已关" }
    private func security(_ value: String?) -> String { switch value { case "normal": "正常"; case "setting": "设防中"; case "active": "已设防"; default: "—" } }
    private func driveMode(_ value: String?) -> String { value == "electric" ? "纯电" : value == "hybrid" ? "混动" : "—" }
    private func healthLabel(_ value: String?) -> String { value == "normal" ? "正常" : value == "warning" ? "异常" : "—" }
    private func unit(_ value: Double?, _ unit: String) -> String { value.map { "\(number($0)) \(unit)" } ?? "—" }
    private func number(_ value: Double?) -> String { guard let value else { return "—" }; return value.formatted(.number.precision(.fractionLength(0...2))) }
    private func cleanName(_ value: String) -> String { value.replacingOccurrences(of: #"^\s*\d{2}款\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces).isEmpty ? "车辆" : value.replacingOccurrences(of: #"^\s*\d{2}款\s*"#, with: "", options: .regularExpression) }
}

private extension VehicleSnapshot.State { var label: String { switch self { case .parked: "已熄火"; case .ready: "已启动"; case .driving: "行驶中"; case .charging: "充电中"; case .fault: "车辆异常" } } }
private extension Color { static let openHomeAuto = Color(red: 0.435, green: 0.396, blue: 0.349) }
