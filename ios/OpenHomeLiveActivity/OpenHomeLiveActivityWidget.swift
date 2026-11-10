import ActivityKit
import SwiftUI
import WidgetKit

struct OpenHomeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OpenHomeStatusAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.attributes.provider == .auto ? "car.side" : "washer")
                    .frame(width: 36, height: 36).background(.teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.resourceName).font(.headline)
                    HStack(spacing: 5) {
                        Text(context.state.state)
                        if let detail = context.state.detail { Text("·"); Text(detail).lineLimit(1) }
                    }.font(.caption).foregroundStyle(.secondary)
                    if let progress = context.state.progress {
                        ProgressView(value: min(max(progress, 0), 1)).tint(.teal)
                    }
                }
                Spacer()
                if let end = context.state.expectedEnd { Text(timerInterval: timerRange(ending: end), countsDown: true).monospacedDigit().font(.headline) }
            }.padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: context.attributes.provider == .auto ? "car.side" : "washer") }
                DynamicIslandExpandedRegion(.center) { VStack(spacing: 1) { Text(context.attributes.resourceName).font(.headline); Text(context.state.state).font(.caption).foregroundStyle(.secondary) } }
                DynamicIslandExpandedRegion(.trailing) { if let progress = context.state.progress { Text(progress, format: .percent.precision(.fractionLength(0))) } }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        Text(context.state.detail ?? context.state.state).font(.caption)
                        if let progress = context.state.progress { ProgressView(value: min(max(progress, 0), 1)).tint(.teal) }
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.provider == .auto ? "car.side" : "washer")
            } compactTrailing: {
                if let end = context.state.expectedEnd { Text(timerInterval: timerRange(ending: end), countsDown: true).monospacedDigit().frame(width: 42) }
                else { Text(context.state.state.prefix(2)) }
            } minimal: {
                Image(systemName: context.attributes.provider == .auto ? "car.side" : "washer")
            }
        }
    }

    private func timerRange(ending end: Date) -> ClosedRange<Date> { let now = Date(); return now...max(now, end) }
}
