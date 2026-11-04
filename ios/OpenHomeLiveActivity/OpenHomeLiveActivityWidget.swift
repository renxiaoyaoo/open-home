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
                    Text(context.state.state).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let end = context.state.expectedEnd { Text(timerInterval: Date()...end, countsDown: true).monospacedDigit().font(.headline) }
            }.padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: context.attributes.provider == .auto ? "car.side" : "washer") }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.resourceName).font(.headline) }
                DynamicIslandExpandedRegion(.trailing) { if let progress = context.state.progress { Text(progress, format: .percent.precision(.fractionLength(0))) } }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.detail ?? context.state.state).font(.caption) }
            } compactLeading: {
                Image(systemName: context.attributes.provider == .auto ? "car.side" : "washer")
            } compactTrailing: {
                if let end = context.state.expectedEnd { Text(timerInterval: Date()...end, countsDown: true).monospacedDigit().frame(width: 42) }
                else { Text(context.state.state.prefix(2)) }
            } minimal: {
                Image(systemName: context.attributes.provider == .auto ? "car.side" : "washer")
            }
        }
    }
}
