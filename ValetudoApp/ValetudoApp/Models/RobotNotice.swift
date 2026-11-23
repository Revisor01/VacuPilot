import Foundation

/// One entry in a robot's notice bell: error, warning or available update.
struct RobotNotice: Identifiable, Equatable {
    /// Ordered by urgency; the bell's dot takes the colour of the most urgent unseen notice.
    enum Kind: Int, Comparable {
        case update, warning, error

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Source: Equatable {
        case robotError(RobotErrorInfo)
        case consumable
        case dockComponent
        case event(id: String, canDismiss: Bool)
        case update(version: String)
    }

    let id: String
    let kind: Kind
    let icon: String
    let title: String
    let detail: String?
    let date: Date?
    let source: Source

    static func collect(
        error: RobotErrorInfo?,
        consumables: [Consumable],
        dockComponents: [DockComponent],
        events: [ValetudoEvent],
        pendingUpdate: String?,
        consumableThreshold: Double = 20
    ) -> [RobotNotice] {
        var notices: [RobotNotice] = []

        if let error {
            let explanation = error.explanation
            notices.append(RobotNotice(
                id: "error_\(explanation.detail ?? explanation.title)",
                kind: error.severityLevel == .warning || error.severityLevel == .info ? .warning : .error,
                icon: "exclamationmark.triangle.fill",
                title: explanation.title,
                detail: explanation.help,
                date: nil,
                source: .robotError(error)
            ))
        }

        for event in events where !event.processed {
            let explanation = event.errorExplanation
            notices.append(RobotNotice(
                id: "event_\(event.id)",
                kind: event.__class == "ErrorStateValetudoEvent" ? .error : .warning,
                icon: event.iconName,
                title: explanation?.title ?? event.displayName,
                detail: explanation?.help ?? event.message,
                date: event.date,
                source: .event(id: event.id, canDismiss: true)
            ))
        }

        for consumable in consumables where consumable.remainingPercent < consumableThreshold {
            let percent = Int(consumable.remainingPercent.rounded())
            notices.append(RobotNotice(
                id: "consumable_\(consumable.id)",
                kind: .warning,
                icon: "wrench.and.screwdriver.fill",
                title: consumable.displayName,
                detail: String(format: String(localized: "notices.consumable.remaining"), percent),
                date: nil,
                source: .consumable
            ))
        }

        for component in dockComponents where component.needsAttention {
            notices.append(RobotNotice(
                id: "dock_\(component.type)_\(component.value)",
                kind: .warning,
                icon: component.icon,
                title: component.displayName,
                detail: component.valueDisplay,
                date: nil,
                source: .dockComponent
            ))
        }

        if let pendingUpdate {
            notices.append(RobotNotice(
                id: "update_\(pendingUpdate)",
                kind: .update,
                icon: "arrow.down.circle.fill",
                title: String(localized: "notices.update.title"),
                detail: pendingUpdate,
                date: nil,
                source: .update(version: pendingUpdate)
            ))
        }

        return notices.sorted { $0.kind > $1.kind }
    }
}

/// Remembers per robot which notices were already looked at, so only new ones light up the bell.
struct NoticeSeenStore {
    let robotId: UUID
    var defaults: UserDefaults = .standard

    private var key: String { "seen_notices_\(robotId.uuidString)" }

    var seenIds: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// Replaces the seen set with what is showing now; a problem that goes away and returns counts as new again.
    func markSeen(_ notices: [RobotNotice]) {
        defaults.set(notices.map(\.id), forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    /// Most urgent kind among notices not seen yet; nil if nothing is new.
    static func newestKind(of notices: [RobotNotice], seen: Set<String>) -> RobotNotice.Kind? {
        notices.filter { !seen.contains($0.id) }.map(\.kind).max()
    }
}
