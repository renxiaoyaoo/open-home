import ActivityKit
import Foundation

struct OpenHomeStatusAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let state: String
        let detail: String?
        let progress: Double?
        let expectedEnd: Date?
    }

    let provider: ProviderID
    let resourceID: String
    let resourceName: String
}
