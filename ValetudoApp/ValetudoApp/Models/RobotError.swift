import Foundation

// Error object of Valetudo's StatusStateAttribute (ValetudoRobotError); every field optional, older firmware sends none.
struct RobotErrorInfo: Codable, Equatable {
    struct Severity: Codable, Equatable {
        var kind: String?
        var level: String?
    }

    var severity: Severity?
    var subsystem: String?
    var message: String?
    var vendorErrorCode: String?

    init(severity: Severity? = nil, subsystem: String? = nil, message: String? = nil, vendorErrorCode: String? = nil) {
        self.severity = severity
        self.subsystem = subsystem
        self.message = message
        self.vendorErrorCode = vendorErrorCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try? container.decodeIfPresent(Severity.self, forKey: .severity)
        subsystem = try? container.decodeIfPresent(String.self, forKey: .subsystem)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        vendorErrorCode = try? container.decodeIfPresent(String.self, forKey: .vendorErrorCode)
    }

    private var normalizedMessage: String {
        (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // Roborock reports "Unknown error undefined" while a poll lacks the error code; it carries no information.
    var isPlaceholder: Bool {
        let text = normalizedMessage
        if text.isEmpty || text == "no error" || text == "unknown error" { return true }
        if text.hasPrefix("unknown error ") { return numericVendorCode == nil }
        return false
    }

    var isSpecific: Bool { !isPlaceholder }

    var numericVendorCode: String? {
        if let code = vendorErrorCode, !code.isEmpty, code.allSatisfy(\.isNumber) { return code }
        let text = normalizedMessage
        guard text.hasPrefix("unknown error ") else { return nil }
        let suffix = String(text.dropFirst("unknown error ".count))
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber) ? suffix : nil
    }

    var knownKind: RobotErrorKind? { RobotErrorKind(message: message) }

    var severityLevel: RobotErrorSeverity {
        RobotErrorSeverity(rawValue: severity?.level ?? "") ?? .unknown
    }

    // Same key = same fault, so flickering between states does not notify twice.
    var dedupeKey: String {
        isPlaceholder ? "placeholder" : "message:\(normalizedMessage)"
    }

    var explanation: RobotErrorExplanation {
        if isPlaceholder {
            return RobotErrorExplanation(
                title: RobotErrorText.localized("robot_error.unknown.title"),
                help: RobotErrorText.localized("robot_error.placeholder.help"),
                detail: nil
            )
        }
        let originalMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail: String
        if let code = numericVendorCode, normalizedMessage.hasPrefix("unknown error") {
            detail = String(format: RobotErrorText.localized("robot_error.vendor_code %@"), code)
        } else {
            detail = String(format: RobotErrorText.localized("robot_error.original %@"), originalMessage)
        }
        if let kind = knownKind {
            return RobotErrorExplanation(title: kind.title, help: kind.help, detail: detail)
        }
        let fallback = RobotErrorSubsystem(rawValue: subsystem ?? "") ?? .unknown
        return RobotErrorExplanation(title: fallback.title, help: fallback.help, detail: detail)
    }
}

struct RobotErrorExplanation: Equatable {
    let title: String
    let help: String
    // Original robot message or vendor code; nil when the robot sent nothing useful.
    let detail: String?
}

enum RobotErrorSeverity: String {
    case info, warning, error, catastrophic, unknown, none
}

enum RobotErrorSubsystem: String, CaseIterable {
    case core, power, sensors, motors, navigation, attachments, dock, unknown

    var title: String { RobotErrorText.localized("robot_error.subsystem.\(rawValue).title") }
    var help: String { RobotErrorText.localized("robot_error.subsystem.\(rawValue).help") }
}

// Known Valetudo error messages (Roborock, Dreame, Midea), grouped by what the user has to do.
enum RobotErrorKind: String, CaseIterable {
    case ldsJammed = "lds_jammed"
    case ldsBumperJammed = "lds_bumper_jammed"
    case ldsFault = "lds_fault"
    case bumperStuck = "bumper_stuck"
    case wheelLostFloorContact = "wheel_lost_floor_contact"
    case cliffSensor = "cliff_sensor"
    case mainBrushJammed = "main_brush_jammed"
    case sideBrushJammed = "side_brush_jammed"
    case wheelJammed = "wheel_jammed"
    case stuck
    case restrictedArea = "restricted_area"
    case dustbinMissing = "dustbin_missing"
    case dustbinFull = "dustbin_full"
    case filterJammed = "filter_jammed"
    case magneticInterference = "magnetic_interference"
    case lowBattery = "low_battery"
    case chargingError = "charging_error"
    case batteryTemperature = "battery_temperature"
    case sensorDirty = "sensor_dirty"
    case tilted
    case rebootRequired = "reboot_required"
    case fanFault = "fan_fault"
    case dockWithoutPower = "dock_without_power"
    case chargingContactsDirty = "charging_contacts_dirty"
    case cameraDirty = "camera_dirty"
    case mopModule = "mop_module"
    case animalExcrement = "animal_excrement"
    case dockDustBagMissing = "dock_dust_bag_missing"
    case dockDustClogged = "dock_dust_clogged"
    case cleanWaterTank = "clean_water_tank"
    case wastewaterTank = "wastewater_tank"
    case waterTankMissing = "water_tank_missing"
    case dockWaterFilter = "dock_water_filter"
    case dockTray = "dock_tray"
    case navigationFailed = "navigation_failed"
    case carpet

    private static let messages: [String: RobotErrorKind] = [
        "lds jammed": .ldsJammed,
        "lds bumper jammed": .ldsBumperJammed,
        "lds communication error": .ldsFault,
        "lds temperature control failed": .ldsFault,
        "lds temperature out of operating range": .ldsFault,
        "stuck front bumper": .bumperStuck,
        "wheel lost floor contact": .wheelLostFloorContact,
        "cliff sensor dirty or robot on the verge of falling": .cliffSensor,
        "main brush jammed": .mainBrushJammed,
        "side brush jammed": .sideBrushJammed,
        "wheel jammed": .wheelJammed,
        "robot stuck or trapped": .stuck,
        "robot stuck in narrow area": .stuck,
        "rotation timeout": .stuck,
        "stuck inside restricted area": .restrictedArea,
        "robot trapped by virtual restrictions": .restrictedArea,
        "dustbin missing": .dustbinMissing,
        "dustbin full": .dustbinFull,
        "filter jammed": .filterJammed,
        "magnetic interference": .magneticInterference,
        "low battery": .lowBattery,
        "charging error": .chargingError,
        "battery temperature out of operating range": .batteryTemperature,
        "wall sensor dirty": .sensorDirty,
        "sensor dirty": .sensorDirty,
        "tilted robot": .tilted,
        "side brush error. reboot required": .rebootRequired,
        "fan error. reboot required": .rebootRequired,
        "fan speed abnormal": .fanFault,
        "charging station without power": .dockWithoutPower,
        "charging contacts dirty": .chargingContactsDirty,
        "charging station dirty": .chargingContactsDirty,
        "camera dirty": .cameraDirty,
        "mop module stuck": .mopModule,
        "mop lift error": .mopModule,
        "lost mop pad": .mopModule,
        "failed to attach mop pads": .mopModule,
        "mop pads not in the dock. attach failed.": .mopModule,
        "animal excrements detected": .animalExcrement,
        "auto-empty dock dustbin or dust bag missing": .dockDustBagMissing,
        "auto-empty dock cover open or missing dust bag": .dockDustBagMissing,
        "auto-empty dock filter clogged": .dockDustClogged,
        "auto-empty dock dust bag full or dust duct clogged": .dockDustClogged,
        "auto-empty dock dust collection error": .dockDustClogged,
        "auto-empty dock dust collection interrupted": .dockDustClogged,
        "mop dock clean water tank empty or not installed": .cleanWaterTank,
        "mop dock clean water tank empty": .cleanWaterTank,
        "mop dock clean water tank not installed": .cleanWaterTank,
        "water tank empty": .cleanWaterTank,
        "mop dock wastewater tank full or not installed": .wastewaterTank,
        "mop dock wastewater tank not installed or full": .wastewaterTank,
        "water tank missing": .waterTankMissing,
        "mop dock water filter not installed": .dockWaterFilter,
        "mop dock water filter clogged": .dockWaterFilter,
        "mop dock tray full of water": .dockTray,
        "mop dock tray not installed": .dockTray,
        "mop dock wastewater pipe clogged": .dockTray,
        "mop dock cleaning brush jammed": .dockTray,
        "cannot reach target": .navigationFailed,
        "cannot navigate to the dock": .navigationFailed,
        "robot failed to exit dock": .navigationFailed,
        "localization error": .navigationFailed,
        "navigation map error": .navigationFailed,
        "map creation error": .navigationFailed,
        "cannot start on carpet": .carpet,
        "attempted to start mopping while on carpet": .carpet
    ]

    init?(message: String?) {
        guard let message else { return nil }
        let key = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let kind = Self.messages[key] else { return nil }
        self = kind
    }

    var title: String { RobotErrorText.localized("robot_error.\(rawValue).title") }
    var help: String { RobotErrorText.localized("robot_error.\(rawValue).help") }
}

enum RobotErrorText {
    // Keys are built at runtime, so they are looked up directly instead of through String(localized:) literals.
    static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
}

extension RobotStatus {
    var robotError: RobotErrorInfo? {
        attributes.first { $0.__class == "StatusStateAttribute" }?.error
    }
}
