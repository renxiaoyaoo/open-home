import Observation
import SwiftUI

@MainActor
@Observable
final class DryerViewModel {
    var snapshot: DryerSnapshot?
    var programs: [DryerProgram] = []
    var programGroup = "日常程序"
    var showsAllPrograms = false
    var scheduledStart = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now) ?? .now
    var parameterValues: [String: Int] = [:]
    var programPresentation: DryerProgram?
    var isLoading = false
    var isOperating = false
    var message: String?
    var lastUpdatedAt: Date?
    private let provider: any DryerProvider
    private let liveStatus: LiveStatusManager
    private var activityID: String?
    private var refreshInFlight = false

    var refreshInterval: Duration {
        switch snapshot?.state { case .running, .paused, .scheduled: return .seconds(5); default: return .seconds(30) }
    }
    var selectedProgram: DryerProgram? {
        if let programPresentation, programPresentation.value == snapshot?.programID { return programPresentation }
        return programs.first { $0.value == snapshot?.programID && ($0.group != "DIY" || snapshot?.programName == $0.name) }
    }
    var visiblePrograms: [DryerProgram] {
        let values = programs.filter { $0.group == programGroup }
        guard !showsAllPrograms, programGroup != "DIY" else { return values }
        let common = programGroup == "日常程序" ? [2, 43, 42, 26] : [6, 0, 14, 15]
        return common.compactMap { id in values.first { $0.value == id } }
    }
    var canChangeProgram: Bool {
        guard !isOperating else { return false }
        switch snapshot?.state { case .running, .scheduled: return false; default: return snapshot?.state != .off }
    }

    init(provider: any DryerProvider, registrar: (any LiveActivityRegistrar)? = nil) {
        self.provider = provider; liveStatus = LiveStatusManager(registrar: registrar)
        if let cached = ModuleContentStore.load("dryer.json", as: DryerCache.self) { snapshot = cached.snapshot; programs = cached.programs; lastUpdatedAt = cached.updatedAt }
    }

    func discardDisplayedContent() { snapshot = nil; programs = []; message = nil }

    func refresh(showLoading: Bool = true) async {
        let revision = ModuleContentStore.revision
        guard !ModuleContentStore.isBlocked("dryer.json") else { discardDisplayedContent(); return }
        guard !refreshInFlight, !isOperating else { return }
        refreshInFlight = true
        if showLoading { isLoading = true }
        defer { refreshInFlight = false; if showLoading { isLoading = false } }
        do {
            let value = try await provider.snapshot()
            guard revision == ModuleContentStore.revision, !ModuleContentStore.isBlocked("dryer.json") else { discardDisplayedContent(); return }
            if value.programID != snapshot?.programID { programPresentation = nil }
            snapshot = value; parameterValues = value.parameters; message = nil; lastUpdatedAt = .now; await updateLiveStatus(value)
            if programs.isEmpty { programs = (try? await provider.programs()) ?? [] }
            guard revision == ModuleContentStore.revision, !ModuleContentStore.isBlocked("dryer.json") else { discardDisplayedContent(); return }
            ModuleContentStore.save("dryer.json", DryerCache(snapshot: value, programs: programs, updatedAt: lastUpdatedAt))
        } catch is CancellationError { return }
        catch let error as URLError where error.code == .cancelled { return }
        catch let error as APIError {
            if case .providerAuthenticationRequired = error { discardDisplayedContent() }
            message = error.localizedDescription
        }
        catch { message = error is URLError ? "无法连接 OpenHome" : error.localizedDescription }
    }
    func select(_ program: DryerProgram) async {
        guard canChangeProgram else { return }
        parameterValues = defaultParameters(program)
        programPresentation = program
        guard await operate(operation: { try await provider.selectProgram(program) }) else { programPresentation = nil; return }
        await confirmProgram(program)
    }
    func configure(_ program: DryerProgram, parameters: [String: Int]) async -> Bool {
        guard canChangeProgram else { return false }
        let succeeded = await operate { try await provider.configureProgram(program, parameters: parameters) }
        if succeeded { programPresentation = program; parameterValues = parameters; await confirmProgram(program) }
        return succeeded
    }
    func togglePower() async { await operate { try await provider.setPower(snapshot?.state == .off) } }
    func primaryAction() async {
        switch snapshot?.state { case .scheduled: await operate { try await provider.command(.cancelSchedule) }; case .running: await operate { try await provider.command(.pause) }; default: await operate { try await provider.command(.start) } }
    }
    func schedule() async {
        guard let program = selectedProgram else { return }
        let finish = expectedFinish(for: program) ?? .now
        let delay = max(1, Int(ceil(finish.timeIntervalSinceNow / 60)))
        await operate(extraDelay: .seconds(3)) { try await provider.command(.schedule(delayMinutes: delay)) }
    }
    func expectedFinish(for program: DryerProgram?) -> Date? {
        guard let program else { return nil }
        let calendar = Calendar.current; let now = Date(); let components = calendar.dateComponents([.hour, .minute], from: scheduledStart)
        var start = calendar.date(bySettingHour: components.hour ?? 23, minute: components.minute ?? 0, second: 0, of: now) ?? now
        if start <= now { start = calendar.date(byAdding: .day, value: 1, to: start) ?? start }
        return calendar.date(byAdding: .minute, value: duration(for: program), to: start)
    }
    func defaultParameters(_ program: DryerProgram) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: (program.parameters ?? []).compactMap { parameter in
            guard parameter.values.indices.contains(parameter.defaultIndex) else { return nil }
            return (parameter.property, parameter.values[parameter.defaultIndex].value)
        })
    }
    func duration(for program: DryerProgram) -> Int {
        program.minutes + ((parameterValues["dry_time_new"] ?? defaultParameters(program)["dry_time_new"]) ?? 0)
    }
    @discardableResult private func operate(extraDelay: Duration = .seconds(1), operation: () async throws -> Void) async -> Bool {
        guard !isOperating else { return false }
        isOperating = true; defer { isOperating = false }
        do { try await operation(); try? await Task.sleep(for: extraDelay); let value = try await provider.snapshot(); snapshot = value; message = nil; await updateLiveStatus(value); return true }
        catch { message = error.localizedDescription; return false }
    }
    private func confirmProgram(_ program: DryerProgram) async {
        for _ in 0..<2 where snapshot?.programID != program.value {
            try? await Task.sleep(for: .seconds(1))
            if let value = try? await provider.snapshot() { snapshot = value; if !value.parameters.isEmpty { parameterValues = value.parameters } }
        }
        if snapshot?.programID != program.value { message = "设备未确认程序切换" }
    }
    private func updateLiveStatus(_ value: DryerSnapshot) async {
        let active = value.state == .running || value.state == .scheduled || value.state == .paused
        let state = OpenHomeStatusAttributes.ContentState(title: value.name, state: value.state.label, detail: value.programName, progress: nil, expectedEnd: value.expectedFinish)
        if active, let activityID, await liveStatus.update(activityID: activityID, state: state) { return }
        else if active { activityID = try? await liveStatus.start(attributes: .init(provider: .living, resourceID: value.deviceID, resourceName: value.name), state: state) }
        else if let activityID { await liveStatus.end(activityID: activityID, state: state); self.activityID = nil }
    }
}

struct DryerView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: DryerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmsPowerOff = false
    @State private var configuringProgram: DryerProgram?
    init(provider: any DryerProvider, registrar: (any LiveActivityRegistrar)? = nil) { _model = State(initialValue: DryerViewModel(provider: provider, registrar: registrar)) }

    var body: some View {
        Group {
            if let value = model.snapshot {
                List {
                    Section {
                        infoRow("状态", value.state.label, tone: statusTone(value.state.label))
                        LabeledContent("剩余") {
                            digitalClock(value.remainingMinutes, blinking: value.state == .running || value.state == .paused || value.state == .scheduled)
                                .font(.title3.weight(.semibold)).monospacedDigit()
                        }
                        infoRow("程序", value.programName ?? "未选择程序")
                        infoRow("更新时间", model.lastUpdatedAt.map(openHomeTimeText) ?? "未知")
                    } header: {
                        Text(value.name).font(.title3.weight(.semibold)).foregroundStyle(.primary).textCase(nil)
                    }
                    Section {
                        HStack(spacing: 12) {
                            Button { if value.state == .off { Task { await model.togglePower() } } else { confirmsPowerOff = true } } label: {
                                Label(value.state == .off ? "开机" : "关机", systemImage: "power").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(model.isOperating)
                            Button { Task { await model.primaryAction() } } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: actionSymbol(value.state)).symbolRenderingMode(.monochrome)
                                    Text(actionTitle(value.state))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(model.isOperating || value.state == .off)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    Section("预约") {
                        infoRow("程序", model.selectedProgram?.name ?? "请选择程序")
                        DatePicker("开始", selection: $model.scheduledStart, displayedComponents: .hourAndMinute).disabled(value.state == .scheduled || value.state == .running)
                        infoRow("预计完成", model.expectedFinish(for: model.selectedProgram)?.formatted(date: .omitted, time: .shortened) ?? "—")
                    }
                    Section {
                        Button { Task { await model.schedule() } } label: {
                            Text(value.state == .scheduled ? "已预约" : "确认预约").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(model.isOperating || value.state == .scheduled || model.selectedProgram == nil || value.state == .running || value.state == .off)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    Section("程序") {
                        Picker("分类", selection: $model.programGroup) { ForEach(["日常程序", "特定材质", "DIY"], id: \.self) { Text($0).tag($0) } }
                            .pickerStyle(.segmented)
                            .onChange(of: model.programGroup) { _, _ in model.showsAllPrograms = false }
                        ForEach(model.visiblePrograms) { program in
                            let selected = program.value == model.snapshot?.programID && (program.group != "DIY" || program.name == model.snapshot?.programName)
                            Button { Task { await model.select(program) } } label: {
                                HStack {
                                    Text(program.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(program.minutes) 分钟").foregroundStyle(.secondary)
                                    if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }
                            }
                            .disabled(!model.canChangeProgram)
                        }
                        if model.programGroup != "DIY", model.programs.filter({ $0.group == model.programGroup }).count > 4 {
                            Button(model.showsAllPrograms ? "收起" : "更多") { model.showsAllPrograms.toggle() }
                        }
                        if let selected = model.selectedProgram, selected.group == model.programGroup, !(selected.parameters ?? []).isEmpty, model.canChangeProgram {
                            Button("参数设置") { configuringProgram = selected }
                        }
                    }
                    if let message = model.message { Section { Text(message).foregroundStyle(.red) } }
                }
                .listStyle(.insetGrouped)
            } else if model.isLoading { ProgressView("正在读取干衣机").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { OpenHomeUnavailable(title: "还没有干衣机内容", systemImage: "washer", description: model.message, actionTitle: "重试") { Task { await model.refresh() } } }
        }
        .onChange(of: appModel.sessionRevision) { _, _ in model.discardDisplayedContent() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refresh(showLoading: model.snapshot == nil)
            while !Task.isCancelled {
                try? await Task.sleep(for: model.refreshInterval)
                guard !Task.isCancelled else { return }
                await model.refresh(showLoading: false)
            }
        }
        .refreshable { await model.refresh() }
        .confirmationDialog("关机？", isPresented: $confirmsPowerOff, titleVisibility: .visible) {
            Button("确认关机", role: .destructive) { Task { await model.togglePower() } }; Button("取消", role: .cancel) {}
        } message: { Text(model.snapshot?.state == .scheduled ? "关机会同时取消当前预约。" : "干衣机将停止运行。") }
        .sheet(item: $configuringProgram) { program in
            DryerProgramSettingsView(program: program, current: model.parameterValues.isEmpty ? model.defaultParameters(program) : model.parameterValues) { parameters in
                await model.configure(program, parameters: parameters)
            }
        }
    }

    private func programButton(_ program: DryerProgram, selected: Bool) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(program.name).font(.body).lineLimit(1)
            Text("\(program.minutes) 分钟").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, 12)
        return Group {
            if selected {
                Button { Task { await model.select(program) } } label: { label }.buttonStyle(.borderedProminent).disabled(!model.canChangeProgram)
            } else {
                Button { Task { await model.select(program) } } label: { label }.buttonStyle(.bordered).disabled(!model.canChangeProgram)
            }
        }
    }
    private func statusCard(_ value: DryerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value.programName ?? "未选择程序").font(.title2.weight(.semibold)).lineLimit(2)
            LabeledContent("当前状态", value: value.state.label)
            HStack(alignment: .firstTextBaseline) {
                Text("剩余时间").foregroundStyle(.secondary)
                Spacer()
                digitalClock(value.remainingMinutes, blinking: value.state == .running || value.state == .paused || value.state == .scheduled).font(.largeTitle.weight(.medium)).monospacedDigit().minimumScaleFactor(0.75).lineLimit(1)
            }
        }
    }
    private func scheduleCard(_ value: DryerSnapshot) -> some View {
        VStack(spacing: 10) {
            HStack { Label("预约", systemImage: "calendar.badge.clock").font(.headline); Spacer(); Text(model.selectedProgram?.name ?? "请选择程序").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                VStack(alignment: .leading) { Text("开始").font(.caption2).foregroundStyle(.secondary); DatePicker("开始", selection: $model.scheduledStart, displayedComponents: .hourAndMinute).labelsHidden().disabled(value.state == .scheduled || value.state == .running) }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading) { Text("预计完成").font(.caption2).foregroundStyle(.secondary); Text(model.expectedFinish(for: model.selectedProgram)?.formatted(date: .omitted, time: .shortened) ?? "—").font(.headline.monospacedDigit()) }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { Task { await model.schedule() } } label: { Label(value.state == .scheduled ? "已预约" : "确认预约", systemImage: "calendar.badge.checkmark").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isOperating || value.state == .scheduled || model.selectedProgram == nil || value.state == .running || value.state == .off)
        }
    }
    private var programCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("程序分类", selection: $model.programGroup) { ForEach(["日常程序", "特定材质", "DIY"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).controlSize(.large).onChange(of: model.programGroup) { _, _ in model.showsAllPrograms = false }
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
                ForEach(model.visiblePrograms) { program in
                    let selected = program.value == model.snapshot?.programID && (program.group != "DIY" || program.name == model.snapshot?.programName)
                    Button { Task { await model.select(program) } } label: { HStack(spacing: 9) { Image(systemName: programSymbol(program.icon)).frame(width: 30, height: 30).background(selected ? Color.openHomeLiving : Color.openHomeLiving.opacity(0.10), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(selected ? .white : Color.openHomeLiving); VStack(alignment: .leading, spacing: 2) { Text(program.name).font(.subheadline.bold()).lineLimit(1); Text("\(program.minutes) 分钟").font(.caption2).foregroundStyle(.secondary) }; Spacer() }.padding(10).frame(minHeight: 58).background(selected ? Color.openHomeLiving.opacity(0.10) : Color.openHomeBackground, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain).disabled(!model.canChangeProgram)
                }
            }
            if model.programGroup != "DIY", model.programs.filter({ $0.group == model.programGroup }).count > 4 { Button(model.showsAllPrograms ? "收起" : "更多") { model.showsAllPrograms.toggle() }.font(.caption.bold()).frame(maxWidth: .infinity) }
            if let selected = model.selectedProgram, selected.group == model.programGroup, !(selected.parameters ?? []).isEmpty, model.canChangeProgram {
                Button { configuringProgram = selected } label: {
                    HStack { VStack(alignment: .leading, spacing: 2) { Text(selected.name).font(.subheadline.bold()); if let description = selected.description { Text(description).font(.caption2).foregroundStyle(.secondary).lineLimit(2) } }; Spacer(); Text("参数设置").font(.subheadline); Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
    }
    private func controlCard(_ value: DryerSnapshot) -> some View {
        HStack(spacing: 10) {
            Button { if value.state == .off { Task { await model.togglePower() } } else { confirmsPowerOff = true } } label: { Label(value.state == .off ? "开机" : "关机", systemImage: "power") }.buttonStyle(.bordered).disabled(model.isOperating)
            Spacer()
            Button { Task { await model.primaryAction() } } label: { Label(actionTitle(value.state), systemImage: actionSymbol(value.state)) }.buttonStyle(.borderedProminent).disabled(model.isOperating || value.state == .off)
        }
    }
    private func infoRow(_ title: String, _ value: String, tone: Color = .secondary) -> some View {
        LabeledContent(title) { Text(value).foregroundStyle(tone) }
    }
    private func digitalClock(_ minutes: Int?, blinking: Bool) -> some View {
        let value = max(0, minutes ?? 0); let hours = String(format: "%02d", value / 60); let remainder = String(format: "%02d", value % 60)
        return TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let bright = !blinking || Int(context.date.timeIntervalSince1970 * 2) % 2 == 0
            HStack(spacing: 0) { Text(hours); Text(":").opacity(bright ? 1 : 0.18); Text(remainder) }
                .accessibilityElement(children: .ignore).accessibilityLabel("\(hours) 小时 \(remainder) 分钟")
        }
    }
    private func actionTitle(_ state: DryerSnapshot.State) -> String { switch state { case .scheduled: "取消预约"; case .running: "暂停"; case .paused: "继续"; default: "启动" } }
    private func actionSymbol(_ state: DryerSnapshot.State) -> String { switch state { case .scheduled: "xmark"; case .running: "pause.fill"; default: "play.fill" } }
    private func programSymbol(_ icon: String) -> String { switch icon { case "large", "bedding": "bed.double.fill"; case "timed": "timer"; case "warm": "flame.fill"; case "fresh": "wind"; case "sport": "figure.run"; case "shirt": "tshirt.fill"; default: "sparkles" } }
}

private struct DryerProgramSettingsView: View {
    let program: DryerProgram
    let apply: ([String: Int]) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [String: Int]
    @State private var isApplying = false
    @State private var message: String?

    init(program: DryerProgram, current: [String: Int], apply: @escaping ([String: Int]) async -> Bool) {
        self.program = program; self.apply = apply; _selection = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) { Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(Color.openHomeLiving); VStack(alignment: .leading, spacing: 2) { Text(program.name).font(.headline); Text("运行时长 \(duration) 分钟").font(.caption).foregroundStyle(.secondary) } }
                    if let description = program.description { Text(description).font(.subheadline).foregroundStyle(.secondary) }
                }
                ForEach(program.parameters ?? []) { parameter in
                    Section(parameter.name) {
                        Picker(parameter.name, selection: Binding(get: { selection[parameter.property] ?? defaultValue(parameter) }, set: { selection[parameter.property] = $0 })) {
                            ForEach(parameter.values) { option in Text(option.label).tag(option.value) }
                        }.pickerStyle(.inline).labelsHidden()
                        if let description = parameter.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle("参数设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isApplying) }
                ToolbarItem(placement: .confirmationAction) { Button(isApplying ? "应用中…" : "应用") { Task { await submit() } }.disabled(isApplying) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var duration: Int { program.minutes + (selection["dry_time_new"] ?? 0) }
    private func defaultValue(_ parameter: DryerProgramParameter) -> Int { parameter.values.indices.contains(parameter.defaultIndex) ? parameter.values[parameter.defaultIndex].value : parameter.values.first?.value ?? 0 }
    @MainActor private func submit() async { isApplying = true; message = nil; let succeeded = await apply(selection); isApplying = false; if succeeded { dismiss() } else { message = "参数设置失败，请重试" } }
}

private struct DryerCache: Codable { var snapshot: DryerSnapshot; var programs: [DryerProgram]; var updatedAt: Date? }
extension DryerSnapshot.State { var label: String { switch self { case .off: "已关机"; case .idle: "待机"; case .running: "烘干中"; case .paused: "已暂停"; case .scheduled: "已预约"; case .finished: "已完成"; case .fault: "设备故障" } } }
private extension Color { static let openHomeLiving = Color(red: 0.286, green: 0.420, blue: 0.443) }
