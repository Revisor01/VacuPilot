import Foundation

/// Statuswechsel eines Roboters, der eine Benachrichtigung auslöst.
enum RobotStateEvent: Equatable {
    case cleaningComplete(area: Int?)
    case stuck
    case error(String?)
}

extension RobotStatus {
    /// Ereignisse beim Wechsel vom unmittelbar vorherigen Stand auf diesen.
    func stateEvents(since previous: RobotStatus?) -> [RobotStateEvent] {
        guard let prevStatus = previous?.statusValue else { return [] }
        let currentStatus = statusValue ?? ""
        var events: [RobotStateEvent] = []
        if prevStatus == "cleaning" && (currentStatus == "docked" || currentStatus == "idle") {
            events.append(.cleaningComplete(area: cleanedArea))
        }
        if statusFlag == "stuck" && previous?.statusFlag != "stuck" {
            events.append(.stuck)
        }
        if currentStatus == "error" && prevStatus != "error" {
            events.append(.error(statusFlag))
        }
        return events
    }
}

/// Merkt sich je Roboter den letzten Stand, damit jeder Wechsel genau einmal gemeldet wird.
final class RobotStateTracker {
    private var last: [UUID: RobotStatus] = [:]

    /// Liefert die Ereignisse gegenüber dem zuletzt übergebenen Stand und merkt sich den neuen.
    func apply(_ status: RobotStatus, for id: UUID) -> [RobotStateEvent] {
        let events = status.stateEvents(since: last[id])
        last[id] = status
        return events
    }

    /// Vergisst den Stand eines entfernten Roboters.
    func forget(_ id: UUID) {
        last.removeValue(forKey: id)
    }
}
