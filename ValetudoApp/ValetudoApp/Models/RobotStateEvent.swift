import Foundation

/// Statuswechsel eines Roboters, der eine Benachrichtigung auslöst.
enum RobotStateEvent: Equatable {
    case cleaningComplete(area: Int?)
    case stuck
    case error(RobotErrorInfo?)
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
            events.append(.error(robotError))
        }
        return events
    }
}

/// Merkt sich je Roboter den letzten Stand, damit jeder Wechsel genau einmal gemeldet wird.
final class RobotStateTracker {
    // Roborock flips between a fault, "Unknown error undefined" and paused within seconds; within this window it counts as one fault.
    static let errorMemoryWindow: TimeInterval = 10 * 60

    private struct ErrorMemory {
        var known: RobotErrorInfo?
        var lastSeen: Date
        var notifiedKey: String?
    }

    private var last: [UUID: RobotStatus] = [:]
    private var errorMemory: [UUID: ErrorMemory] = [:]
    private var displayed: [UUID: RobotErrorInfo] = [:]

    /// Liefert die Ereignisse gegenüber dem zuletzt übergebenen Stand und merkt sich den neuen.
    func apply(_ status: RobotStatus, for id: UUID, at now: Date = Date()) -> [RobotStateEvent] {
        let previous = last[id]
        last[id] = status
        var events = status.stateEvents(since: previous).filter {
            if case .error = $0 { return false }
            return true
        }

        guard status.isOnline, status.statusValue == "error" else {
            displayed.removeValue(forKey: id)
            return events
        }

        var memory = errorMemory[id] ?? ErrorMemory(known: nil, lastSeen: now, notifiedKey: nil)
        if now.timeIntervalSince(memory.lastSeen) > Self.errorMemoryWindow {
            memory = ErrorMemory(known: nil, lastSeen: now, notifiedKey: nil)
        }
        let current = status.robotError
        if let current, current.isSpecific {
            memory.known = current
        }
        memory.lastSeen = now

        let resolved = memory.known ?? current
        if let resolved {
            displayed[id] = resolved
        } else {
            displayed.removeValue(forKey: id)
        }

        let key = resolved?.dedupeKey ?? "placeholder"
        let isSpecific = resolved?.isSpecific ?? false
        let alreadyNotified = memory.notifiedKey == key || (memory.notifiedKey != nil && !isSpecific)
        if !alreadyNotified {
            // Without a previous online state (app start, reconnect) the fault is shown but not announced.
            if previous?.statusValue != nil {
                events.append(.error(resolved))
            }
            memory.notifiedKey = key
        }
        errorMemory[id] = memory
        return events
    }

    /// Fehler, den die Oberfläche zeigen soll: die letzte konkrete Meldung statt eines kurz dazwischenfunkenden Platzhalters.
    func displayedError(for id: UUID) -> RobotErrorInfo? {
        displayed[id]
    }

    /// Vergisst den Stand eines entfernten Roboters.
    func forget(_ id: UUID) {
        last.removeValue(forKey: id)
        errorMemory.removeValue(forKey: id)
        displayed.removeValue(forKey: id)
    }
}
