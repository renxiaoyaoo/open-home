import ActivityKit
import Foundation

@MainActor
final class LiveStatusManager {
    private let registrar: (any LiveActivityRegistrar)?
    private var tokenTasks: [String: Task<Void, Never>] = [:]

    init(registrar: (any LiveActivityRegistrar)? = nil) { self.registrar = registrar }

    func start(attributes: OpenHomeStatusAttributes, state: OpenHomeStatusAttributes.ContentState) async throws -> String {
        if let activity = Activity<OpenHomeStatusAttributes>.activities.first(where: { $0.attributes.provider == attributes.provider && $0.attributes.resourceID == attributes.resourceID }) {
            await activity.update(.init(state: state, staleDate: state.expectedEnd))
            observePushToken(for: activity)
            return activity.id
        }
        let activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: state.expectedEnd), pushType: registrar == nil ? nil : .token)
        observePushToken(for: activity)
        return activity.id
    }

    @discardableResult
    func update(activityID: String, state: OpenHomeStatusAttributes.ContentState) async -> Bool {
        guard let activity = Activity<OpenHomeStatusAttributes>.activities.first(where: { $0.id == activityID }) else {
            tokenTasks.removeValue(forKey: activityID)?.cancel()
            return false
        }
        await activity.update(.init(state: state, staleDate: state.expectedEnd))
        observePushToken(for: activity)
        return true
    }

    func end(activityID: String, state: OpenHomeStatusAttributes.ContentState) async {
        guard let activity = Activity<OpenHomeStatusAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .default)
        tokenTasks.removeValue(forKey: activityID)?.cancel()
        await registrar?.unregister(activityID: activityID)
    }

    private func observePushToken(for activity: Activity<OpenHomeStatusAttributes>) {
        guard let registrar, tokenTasks[activity.id] == nil else { return }
        tokenTasks[activity.id] = Task {
            for await token in activity.pushTokenUpdates {
                try? await registrar.register(activityID: activity.id, provider: activity.attributes.provider, resourceID: activity.attributes.resourceID, pushToken: token)
            }
        }
    }
}
