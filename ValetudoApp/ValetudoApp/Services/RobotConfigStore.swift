import Foundation

// Where saved robots live: ID list in UserDefaults, each config in the Keychain; older installs still have the legacy list.
enum RobotConfigStore {
    static let idsKey = "valetudo_robot_ids"
    static let legacyKey = "valetudo_robots"

    static func savedRobots(defaults: UserDefaults = .standard,
                            loadConfig: (UUID) -> RobotConfig? = KeychainStore.robotConfig(for:)) -> [RobotConfig] {
        guard let data = defaults.data(forKey: idsKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return [] }
        return ids.compactMap(loadConfig)
    }

    static func legacyRobots(defaults: UserDefaults = .standard) -> [RobotConfig] {
        guard let data = defaults.data(forKey: legacyKey),
              let configs = try? JSONDecoder().decode([RobotConfig].self, from: data) else { return [] }
        return configs
    }

    // Read-only: migrating the legacy list is left to the app in the foreground.
    static func robotsForBackgroundCheck(defaults: UserDefaults = .standard,
                                         loadConfig: (UUID) -> RobotConfig? = KeychainStore.robotConfig(for:)) -> [RobotConfig] {
        let saved = savedRobots(defaults: defaults, loadConfig: loadConfig)
        return saved.isEmpty ? legacyRobots(defaults: defaults) : saved
    }
}
