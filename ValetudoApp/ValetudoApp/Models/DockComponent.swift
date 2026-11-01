import Foundation

// Dock component state (water tanks, detergent, dust bag) from Valetudo's DockComponentStateAttribute.
struct DockComponent: Equatable, Identifiable {
    let type: String
    let value: String

    var id: String { type }

    static let displayOrder = ["water_tank_clean", "water_tank_dirty", "detergent", "dustbag"]

    var needsAttention: Bool {
        ["empty", "missing", "full"].contains(value)
    }

    var displayName: String {
        switch type {
        case "water_tank_clean": return String(localized: "dock_component.water_tank_clean")
        case "water_tank_dirty": return String(localized: "dock_component.water_tank_dirty")
        case "detergent": return String(localized: "consumable.detergent")
        case "dustbag": return String(localized: "dock_component.dustbag")
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var valueDisplay: String {
        switch value {
        case "ok": return String(localized: "dock_component.state.ok")
        case "empty": return String(localized: "dock_component.state.empty")
        case "missing": return String(localized: "dock_component.state.missing")
        case "full": return String(localized: "dock_component.state.full")
        default: return String(localized: "dock_component.state.unknown")
        }
    }

    var icon: String {
        switch type {
        case "water_tank_clean": return "drop.fill"
        case "water_tank_dirty": return "drop.triangle.fill"
        case "detergent": return "bubbles.and.sparkles.fill"
        case "dustbag": return "trash.fill"
        default: return "shippingbox.fill"
        }
    }
}

extension RobotStatus {
    var dockComponents: [DockComponent] {
        let components = attributes.compactMap { attr -> DockComponent? in
            guard attr.__class == "DockComponentStateAttribute", let type = attr.type else { return nil }
            return DockComponent(type: type, value: attr.value ?? "unknown")
        }
        return components.sorted { lhs, rhs in
            let l = DockComponent.displayOrder.firstIndex(of: lhs.type) ?? Int.max
            let r = DockComponent.displayOrder.firstIndex(of: rhs.type) ?? Int.max
            return l < r
        }
    }

    // Only transitions between two online states count, so app start and reconnects stay silent.
    func newDockComponentProblems(since previous: RobotStatus?) -> [DockComponent] {
        guard let previous, previous.isOnline, isOnline else { return [] }
        let before = Dictionary(previous.dockComponents.map { ($0.type, $0.value) }, uniquingKeysWith: { first, _ in first })
        return dockComponents.filter { $0.needsAttention && before[$0.type] != $0.value }
    }
}
