import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Module: String, CaseIterable, Identifiable {
        case gate = "OpenGate"
        case living = "OpenLiving"
        case lock = "OpenLock"
        case auto = "OpenAuto"

        var id: Self { self }
        var subtitle: String {
            switch self {
            case .gate: "门禁"
            case .living: "智能家电"
            case .lock: "智能门锁"
            case .auto: "车辆"
            }
        }
        var symbol: String {
            switch self {
            case .gate: "door.left.hand.open"
            case .living: "washer"
            case .lock: "lock.shield"
            case .auto: "car.side"
            }
        }
    }

    var selectedModule: Module = .gate
    var connection: ConnectionConfiguration?

    init(connectionStore: ConnectionStore = ConnectionStore()) {
        connection = connectionStore.load()
    }
}
