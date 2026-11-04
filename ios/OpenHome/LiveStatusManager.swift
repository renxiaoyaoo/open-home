import ActivityKit
import Foundation

@MainActor
final class LiveStatusManager {
    func start(attributes: OpenHomeStatusAttributes, state: OpenHomeStatusAttributes.ContentState) async throws -> String {
        if let activity = Activity<OpenHomeStatusAttributes>.activities.first(where: { $0.attributes.provider == attributes.provider && $0.attributes.resourceID == attributes.resourceID }) {
            await activity.update(.init(state: state, staleDate: state.expectedEnd))
            return activity.id
        }
        let activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: state.expectedEnd), pushType: nil)
        return activity.id
    }

    func update(activityID: String, state: OpenHomeStatusAttributes.ContentState) async {
        guard let activity = Activity<OpenHomeStatusAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        await activity.update(.init(state: state, staleDate: state.expectedEnd))
    }

    func end(activityID: String, state: OpenHomeStatusAttributes.ContentState) async {
        guard let activity = Activity<OpenHomeStatusAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .default)
    }
}
