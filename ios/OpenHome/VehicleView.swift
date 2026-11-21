import Charts
import Observation
import SwiftUI

@MainActor @Observable final class VehicleViewModel {
    var vehicles: [VehicleResource] = []; var selectedVehicleID = ""
    var snapshot: VehicleSnapshot?; var energy: VehicleEnergy?; var isLoading = false; var message: String?; var signedOut = false
    private let provider: any VehicleProvider; private let liveStatus: LiveStatusManager; private var activityID: String?
    var refreshInterval: Duration { switch snapshot?.state { case .ready, .driving, .charging: .seconds(5); default: .seconds(30) } }
    init(provider: any VehicleProvider, registrar: (any LiveActivityRegistrar)? = nil) {
        self.provider = provider; liveStatus = LiveStatusManager(registrar: registrar)
        if let cached = ModuleContentStore.load("vehicle.json", as: VehicleCache.self) {
            vehicles = cached.vehicles; snapshot = cached.snapshot; energy = cached.energy; selectedVehicleID = cached.snapshot.vehicleID
        }
    }
    func discardDisplayedContent() { vehicles = []; selectedVehicleID = ""; snapshot = nil; energy = nil; message = nil; signedOut = false }

    func loadDetail() async {
        let revision = ModuleContentStore.revision
        guard !ModuleContentStore.isBlocked("vehicle.json") else { clearSignedOut(); return }
        guard !isLoading else { return }; isLoading = true; defer { isLoading = false }
        do {
            vehicles = try await provider.vehicles()
            guard revision == ModuleContentStore.revision, !ModuleContentStore.isBlocked("vehicle.json") else { keepSignedOutState(); return }
            let current = try await provider.snapshot()
            guard revision == ModuleContentStore.revision, !ModuleContentStore.isBlocked("vehicle.json") else { keepSignedOutState(); return }
            snapshot = current.keepingLocation(from: snapshot); signedOut = false; selectedVehicleID = current.vehicleID; message = nil; persist(); await updateLiveStatus(snapshot ?? current)
            let value = try await provider.detail()
            guard revision == ModuleContentStore.revision, !ModuleContentStore.isBlocked("vehicle.json") else { keepSignedOutState(); return }
            snapshot = value.summary.keepingLocation(from: snapshot); signedOut = false; selectedVehicleID = value.summary.vehicleID; energy = value.energy; message = nil; persist(); await updateLiveStatus(snapshot ?? value.summary)
        } catch is CancellationError { return }
        catch let error as URLError where error.code == .cancelled { return }
        catch let error as APIError {
            noteSignedOut(error)
            message = error.localizedDescription
        }
        catch { noteSignedOutMessage(error.localizedDescription); message = error is URLError ? "无法连接 OpenHome" : error.localizedDescription }
    }
    func selectVehicle(_ id: String) async {
        guard id != selectedVehicleID, !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do { try await provider.selectVehicle(id: id); let current = try await provider.snapshot(); selectedVehicleID = id; snapshot = current.keepingLocation(from: snapshot); signedOut = false; message = nil; await updateLiveStatus(snapshot ?? current); let value = try await provider.detail(); snapshot = value.summary.keepingLocation(from: snapshot); energy = value.energy; persist(); await updateLiveStatus(snapshot ?? value.summary) }
        catch { message = error.localizedDescription }
    }
    func refreshStatus() async {
        let revision = ModuleContentStore.revision
        guard !ModuleContentStore.isBlocked("vehicle.json") else { clearSignedOut(); return }
        guard !isLoading else { return }
        do {
            let value = try await provider.snapshot()
            guard revision == ModuleContentStore.revision, !ModuleContentStore.isBlocked("vehicle.json") else { keepSignedOutState(); return }
            snapshot = value.keepingLocation(from: snapshot); signedOut = false; message = nil; persist(); await updateLiveStatus(snapshot ?? value)
        }
        catch is CancellationError { return }
        catch let error as URLError where error.code == .cancelled { return }
        catch let error as APIError {
            noteSignedOut(error)
            message = error.localizedDescription
        }
        catch { noteSignedOutMessage(error.localizedDescription); message = error is URLError ? "无法连接 OpenHome" : error.localizedDescription }
    }
    private func noteSignedOut(_ error: APIError) {
        switch error {
        case .providerAuthenticationRequired, .unauthorized:
            clearSignedOut()
        case .server(_, let message):
            noteSignedOutMessage(message ?? error.localizedDescription)
        default:
            noteSignedOutMessage(error.localizedDescription)
        }
    }
    private func noteSignedOutMessage(_ message: String?) {
        guard message?.contains("登录") == true else { return }
        clearSignedOut()
    }
    private func clearSignedOut() {
        discardDisplayedContent(); signedOut = true; ModuleContentStore.block("vehicle.json")
    }
    private func keepSignedOutState() {
        if ModuleContentStore.isBlocked("vehicle.json") { clearSignedOut() } else { discardDisplayedContent() }
    }
    func applySessionChange() {
        keepSignedOutState()
    }
    private func persist() { guard let snapshot, !signedOut else { return }; ModuleContentStore.save("vehicle.json", VehicleCache(vehicles: vehicles, snapshot: snapshot, energy: energy)) }
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
    @Environment(AppModel.self) private var appModel
    @State private var model: VehicleViewModel; @Environment(\.scenePhase) private var scenePhase
    init(provider: any VehicleProvider, registrar: (any LiveActivityRegistrar)? = nil) { _model = State(initialValue: VehicleViewModel(provider: provider, registrar: registrar)) }
    var body: some View {
        Group {
            if model.signedOut || model.message?.contains("登录") == true { OpenHomeUnavailable(title: "尚未登录", systemImage: "person.crop.circle.badge.xmark", description: model.message) }
            else if let value = model.snapshot { vehicleList(value) }
            else if model.isLoading { ProgressView("正在读取车辆").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { OpenHomeUnavailable(title: "还没有车辆内容", systemImage: "car.side", description: model.message, actionTitle: "重试") { Task { await model.loadDetail() } } }
        }
        .onChange(of: appModel.sessionRevision) { _, _ in model.applySessionChange() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.loadDetail()
            while !Task.isCancelled { try? await Task.sleep(for: model.refreshInterval); await model.refreshStatus() }
        }
        .refreshable { await model.loadDetail() }
    }

    private func vehicleList(_ value: VehicleSnapshot) -> some View {
        List {
            Section {
                valueRow("状态", value.state.label, tone: statusColor(value.state.label))
                valueRow("续航", "\(number(value.totalRangeKM)) km", emphasize: true)
                fuelRow("电", percent: value.batteryPercent, range: value.electricRangeKM)
                fuelRow("油", percent: value.fuelPercent, range: value.fuelRangeKM)
                locationRow(value)
                valueRow("信号", connectionLabel(value), tone: statusColor(connectionLabel(value)))
                valueRow("更新时间", updateValue)
            } header: {
                moduleTitle(displayName(value)) {
                    if model.vehicles.count > 1 { Menu { ForEach(model.vehicles) { vehicle in Button(vehicle.name) { Task { await model.selectVehicle(vehicle.id) } } } } label: { Image(systemName: "chevron.up.chevron.down") }.accessibilityLabel("选择车辆") }
                }
            }
            Section("里程") {
                valueRow("总里程", measure(value.odometerKM, "公里"), emphasize: true)
                valueRow("EV 里程", measure(value.evMileageKM, "公里"))
                valueRow("HEV 里程", measure(value.hevMileageKM, "公里"))
                valueRow("车内温度", measure(value.cabinTemperatureC, "℃"))
            }
            Section("车辆状态") {
                valueRow("车门", doorStatus(value), tone: statusColor(doorStatus(value)))
                valueRow("车窗", opening(value.windowsOpen), tone: statusColor(opening(value.windowsOpen)))
                valueRow("前舱盖", openLabel(value.hoodOpen), tone: statusColor(openLabel(value.hoodOpen)))
                valueRow("后备箱", openLabel(value.trunkOpen), tone: statusColor(openLabel(value.trunkOpen)))
            }
            if let tire = value.tirePressureKPA {
                Section("胎压") { tirePanel(tire) }
            }
            Section("整车状态") {
                valueRow("防盗状态", security(value.securityState), tone: statusColor(security(value.securityState)))
                valueRow("动力模式", driveMode(value.driveMode), tone: statusColor(driveMode(value.driveMode)))
                valueRow("OK 指示灯", value.okIndicator.map { $0 ? "点亮" : "熄灭" } ?? "—", tone: statusColor(value.okIndicator.map { $0 ? "点亮" : "熄灭" } ?? "—"))
                valueRow("行驶状态", value.state.label, tone: statusColor(value.state.label))
                valueRow("车速", unit(value.speedKPH, "公里/小时"))
                valueRow("功率", unit(value.powerOutputKW, "千瓦"))
                valueRow("发动机冷却液温度", unit(value.engineCoolantC, "℃"))
            }
            if let health = value.health { Section("健康检测") { healthRows(health) } }
            if let energy = model.energy {
                Section("最近 \(number(energy.recentDistanceKm ?? 50)) km平均行车能耗") { recentEnergyRows(energy) }
                if let breakdown = energy.breakdown { Section { breakdownChart(breakdown) } }
                if !energy.recentTrend.isEmpty {
                    Section("近期能耗") {
                        trendChart(latestTrend(energy.recentTrend)).frame(maxWidth: .infinity)
                    }
                }
                Section("累计平均能耗") { cumulativeEnergyRows(energy) }
            }
            if let charging = value.chargingState, charging != "unknown" {
                Section("充电") {
                    valueRow("状态", charging == "charging" ? "正在补能" : charging == "complete" ? "已充满" : "未充电", tone: statusColor(charging == "charging" ? "正在补能" : charging == "complete" ? "已充满" : "未充电"))
                    if let power = value.chargingPowerKW { valueRow("功率", "\(number(power)) kW") }
                    if let minutes = value.remainingChargeMinutes { valueRow("剩余", "\(minutes / 60) 小时 \(minutes % 60) 分钟") }
                }
            }
            if let message = model.message { Section { Text(message).foregroundStyle(.red) } }
        }
        .listStyle(.insetGrouped)
    }
    private func moduleTitle(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(.primary).textCase(nil)
            Spacer()
            trailing().textCase(nil)
        }
    }
    private func valueRow(_ title: String, _ value: String, emphasize: Bool = false, tone: Color? = nil) -> some View {
        LabeledContent(title) {
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(tone ?? (emphasize ? Color.primary : Color.secondary)).font(emphasize ? .title3.weight(.semibold) : .body)
        }
    }
    private func statusColor(_ value: String) -> Color { statusTone(value) }
    @ViewBuilder private func healthRows(_ health: [String: String]) -> some View {
        let items = [("发动机", "engine"), ("制动系统", "braking"), ("ABS 系统", "abs"), ("SRS 系统", "srs"), ("胎压监测系统", "tirePressure"), ("电子车身稳定系统", "stability"), ("转向系统", "steering"), ("发动机冷却液温度", "coolant"), ("机油压力", "oilPressure"), ("低压供电系统", "lowVoltage"), ("动力电池", "tractionBattery"), ("动力系统", "powertrain")]
        let overall = health.values.contains("warning") ? "发现异常" : health.values.contains("normal") ? "正常" : "—"
        valueRow("总体", overall, tone: statusColor(overall))
        ForEach(items, id: \.1) { label, key in valueRow(label, healthLabel(health[key]), tone: statusColor(healthLabel(health[key]))) }
    }
    @ViewBuilder private func recentEnergyRows(_ value: VehicleEnergy) -> some View {
        valueRow("电耗", rate(value.electricityKwhPer100Km, "kWh/100km"))
        valueRow("油耗", rate(value.fuelLitresPer100Km, "L/100km"))
        valueRow("综合", rate(value.equivalentFuelLitresPer100Km, "L/100km"))
        if let amount = value.electricityKwh { valueRow("电量", "\(number(amount)) kWh") }
        if let amount = value.fuelLitres { valueRow("油量", "\(number(amount)) L") }
        if let amount = value.costYuan { valueRow("费用", "\(number(amount)) 元") }
        if let rank = value.rankPercent { valueRow("领先同车型", "\(number(rank))%") }
    }
    @ViewBuilder private func cumulativeEnergyRows(_ value: VehicleEnergy) -> some View {
        valueRow("电耗", rate(value.cumulativeElectricityKwhPer100Km, "kWh/100km"))
        valueRow("油耗", rate(value.cumulativeFuelLitresPer100Km, "L/100km"))
        valueRow("综合", rate(value.cumulativeEquivalentFuelLitresPer100Km, "L/100km"))
        valueRow("每公里费用", measure(value.costPerKmYuan, "元"))
        if let rank = value.cumulativeRankPercent { valueRow("领先同车型", "\(number(rank))%") }
    }
    private func fuelRow(_ title: String, percent: Double?, range: Double?) -> some View {
        let tone = levelTone(percent)
        return HStack(spacing: 10) {
            Text(title)
            Spacer(minLength: 12)
            Text(range.map { "\(number($0)) km" } ?? "—").foregroundStyle(.secondary)
            Text(percent.map { "\(Int($0))%" } ?? "—").foregroundStyle(tone)
            ProgressView(value: min(max(percent ?? 0, 0), 100), total: 100)
                .tint(tone)
                .frame(width: 56)
        }
    }
    private func measure(_ value: Double?, _ unit: String) -> String { "\(number(value)) \(unit)" }
    private func rate(_ value: Double?, _ unit: String) -> String { "\(energyNumber(value)) \(unit)" }
    private func breakdownChart(_ value: VehicleEnergyBreakdown) -> some View {
        let parts = [("驱动", value.propulsionPercent, Color.brown), ("空调", value.climatePercent, .teal), ("电器", value.electricalPercent, .orange), ("其他", value.otherPercent, .gray)]
        return VStack(alignment: .leading, spacing: 8) { Text("能耗分布").font(.subheadline.bold()); GeometryReader { geometry in HStack(spacing: 2) { ForEach(parts, id: \.0) { _, percent, color in if let percent, percent > 0 { color.frame(width: max(3, geometry.size.width * percent / 100)) } } } }.frame(height: 10).clipShape(Capsule()); HStack { ForEach(parts, id: \.0) { label, percent, color in if let percent { Label("\(label) \(number(percent))%", systemImage: "circle.fill").foregroundStyle(color).font(.caption2) } } } }
    }
    private func trendChart(_ points: [VehicleEnergyTrendPoint]) -> some View {
        let rows = trendRows(points)
        let labels = trendLabels(rows)
        let last = Double(max(labels.count - 1, 0))
        return VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(rows.filter { $0.series == "同车型" }) { row in
                    LineMark(x: .value("日", row.index), y: .value("L/100km", row.value), series: .value("对象", row.series))
                        .interpolationMethod(.linear)
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                ForEach(rows.filter { $0.series == "我的" }) { row in
                    LineMark(x: .value("日", row.index), y: .value("L/100km", row.value), series: .value("对象", row.series))
                        .interpolationMethod(.linear)
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plot = proxy.plotFrame {
                        let origin = geometry[plot].origin
                        ForEach(rows.filter { $0.series == "我的" }) { row in
                            if let x = proxy.position(forX: row.index), let y = proxy.position(forY: row.value) {
                                Text(energyNumber(row.value))
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                    .position(x: origin.x + x, y: origin.y + y - 14)
                            }
                        }
                    }
                }
            }
            .chartXScale(domain: -0.4...(last + 0.4))
            .chartXAxis {
                AxisMarks(values: Array(labels.indices)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let index = value.as(Int.self), labels.indices.contains(index) {
                            Text(labels[index]).font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYAxisLabel("L/100km")
            .chartLegend(.hidden)
            .chartPlotStyle { plot in plot.padding(.top, 22) }
            .frame(height: 220)
            HStack(spacing: 16) {
                trendKey(color: .green, dashed: false, title: "我的")
                trendKey(color: .orange, dashed: true, title: "同车型")
            }
        }
    }
    private func trendKey(color: Color, dashed: Bool, title: String) -> some View {
        HStack(spacing: 6) {
            Canvas { context, size in
                var path = Path()
                let y = size.height / 2
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .butt, dash: dashed ? [4, 3] : []))
            }
            .frame(width: 22, height: 10)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func connectionLabel(_ value: VehicleSnapshot) -> String {
        guard value.online != false else { return "离线" }
        guard let level = value.signalStrength else { return "在线" }
        return level >= 4 ? "良好" : level >= 2 ? "一般" : "较弱"
    }
    private func locationRow(_ value: VehicleSnapshot) -> some View {
        let location = value.locationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return LabeledContent("停车位置") {
            if let mapURL = location.isEmpty ? nil : mapURL(location) {
                Link(location, destination: mapURL).multilineTextAlignment(.trailing)
            } else {
                Text(location.isEmpty ? "暂无停车位置" : location).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        }
    }
    private var updateValue: String {
        guard let updated = model.snapshot?.updatedAt else { return "未知" }
        return openHomeTimeText(updated)
    }
    private func tirePanel(_ value: VehicleTirePressure) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(spacing: 18) { tire("左前", value.frontLeft); tire("左后", value.rearLeft) }
                Image(systemName: "car.top.radiowaves.front")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .frame(width: 52)
                    .accessibilityLabel("车头朝上")
                VStack(spacing: 18) { tire("右前", value.frontRight); tire("右后", value.rearRight) }
            }
            .frame(maxWidth: .infinity)
        }
    }
    private func tire(_ label: String, _ value: Double?) -> some View {
        let abnormal = value.map { $0 < 220 || $0 > 280 } ?? false
        return VStack(spacing: 2) {
            Text(value.map { number($0) } ?? "—").font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(value == nil ? Color.secondary : (abnormal ? Color.orange : Color.green))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    private func doorStatus(_ value: VehicleSnapshot) -> String { if any(value.doorsOpen) { return "有打开" }; if any(value.doorsUnlocked) { return "已关未锁" }; return value.doorsOpen == nil && value.doorsUnlocked == nil ? "状态未知" : "已关已锁" }
    private func opening(_ value: VehicleCornerState?) -> String { value == nil ? "状态未知" : any(value) ? "有打开" : "已关" }
    private func any(_ value: VehicleCornerState?) -> Bool { [value?.frontLeft, value?.frontRight, value?.rearLeft, value?.rearRight].contains(true) }
    private func openLabel(_ value: Bool?) -> String { value == nil ? "状态未知" : value == true ? "已打开" : "已关" }
    private func security(_ value: String?) -> String { switch value { case "normal": "正常"; case "setting": "设防中"; case "active": "已设防"; default: "—" } }
    private func driveMode(_ value: String?) -> String { value == "electric" ? "纯电" : value == "hybrid" ? "混动" : "—" }
    private func healthLabel(_ value: String?) -> String { value == "normal" ? "正常" : value == "warning" ? "异常" : "—" }
    private func unit(_ value: Double?, _ unit: String) -> String { value.map { "\(number($0)) \(unit)" } ?? "—" }
    private func number(_ value: Double?) -> String { guard let value else { return "—" }; return value.formatted(.number.precision(.fractionLength(0...2))) }
    private func energyNumber(_ value: Double?) -> String { guard let value else { return "—" }; return value.formatted(.number.precision(.fractionLength(1))) }
    private func displayName(_ value: VehicleSnapshot) -> String {
        let listed = model.vehicles.first { $0.id == value.vehicleID }?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleanName(!listed.isEmpty && listed != "车辆" ? listed : value.name)
    }
    private func cleanName(_ value: String) -> String { value.replacingOccurrences(of: #"^\s*\d{2}款\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces).isEmpty ? "车辆" : value.replacingOccurrences(of: #"^\s*\d{2}款\s*"#, with: "", options: .regularExpression) }
    private func mapURL(_ location: String) -> URL? { var components = URLComponents(string: "maps://"); components?.queryItems = [.init(name: "q", value: location)]; return components?.url }
    private func latestTrend(_ points: [VehicleEnergyTrendPoint]) -> [VehicleEnergyTrendPoint] {
        Array(points.sorted { trendDate($0.date) < trendDate($1.date) }.suffix(7))
    }
    private struct TrendRow: Identifiable { let index: Int; let label: String; let series: String; let value: Double; var id: String { "\(series)-\(index)" } }
    private func trendRows(_ points: [VehicleEnergyTrendPoint]) -> [TrendRow] {
        let ordered = points.sorted { trendDate($0.date) < trendDate($1.date) }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "M/d"
        var rows: [TrendRow] = []
        for (index, point) in ordered.enumerated() {
            let label = (VehicleWireDate.parse(point.date) ?? dayDate(point.date)).map { formatter.string(from: $0) } ?? String(point.date.suffix(5))
            if let value = point.equivalentFuelLitresPer100Km { rows.append(.init(index: index, label: label, series: "我的", value: value)) }
            if let value = point.peerAverageLitresPer100Km { rows.append(.init(index: index, label: label, series: "同车型", value: value)) }
        }
        return rows
    }
    private func trendLabels(_ rows: [TrendRow]) -> [String] {
        var labels: [String] = []
        var seen = Set<Int>()
        for row in rows where seen.insert(row.index).inserted { labels.append(row.label) }
        return labels
    }
    private func trendDate(_ value: String) -> String {
        guard let date = VehicleWireDate.parse(value) ?? dayDate(value) else { return value }
        return ISO8601DateFormatter().string(from: date)
    }
    private func dayDate(_ value: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current
        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "MM-dd", "MM/dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

private struct VehicleCache: Codable { var vehicles: [VehicleResource]; var snapshot: VehicleSnapshot; var energy: VehicleEnergy? }
private enum VehicleWireDate {
    static func parse(_ value: String) -> Date? { VehicleDateParsing.parse(value) }
}

private extension VehicleSnapshot {
    func keepingLocation(from previous: VehicleSnapshot?) -> VehicleSnapshot {
        let incoming = locationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard incoming.isEmpty, let kept = previous?.locationName?.trimmingCharacters(in: .whitespacesAndNewlines), !kept.isEmpty, previous?.vehicleID == vehicleID else { return self }
        return VehicleSnapshot(vehicleID: vehicleID, name: name, state: state, chargingState: chargingState, speedKPH: speedKPH, totalRangeKM: totalRangeKM, batteryPercent: batteryPercent, fuelPercent: fuelPercent, electricRangeKM: electricRangeKM, fuelRangeKM: fuelRangeKM, odometerKM: odometerKM, evMileageKM: evMileageKM, hevMileageKM: hevMileageKM, cabinTemperatureC: cabinTemperatureC, locationName: kept, signalStrength: signalStrength, online: online, securityState: securityState, driveMode: driveMode, okIndicator: okIndicator, powerOutputKW: powerOutputKW, engineCoolantC: engineCoolantC, health: health, doorsOpen: doorsOpen, doorsUnlocked: doorsUnlocked, windowsOpen: windowsOpen, hoodOpen: hoodOpen, trunkOpen: trunkOpen, skylightOpen: skylightOpen, tirePressureKPA: tirePressureKPA, chargingPowerKW: chargingPowerKW, remainingChargeMinutes: remainingChargeMinutes, updatedAt: updatedAt)
    }
}
private extension VehicleSnapshot.State { var label: String { switch self { case .parked: "已熄火"; case .ready: "已启动"; case .driving: "行驶中"; case .charging: "充电中"; case .fault: "车辆异常" } } }
