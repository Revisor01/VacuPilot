import Foundation
import OSLog
import Security

struct KeychainStore {
    private static let service = "com.valetudio.robot.password"
    // The background check runs while the phone is locked; WhenUnlocked would hide password and config from it.
    static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VacuPilot", category: "KeychainStore")

    static func password(for robotId: UUID) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: robotId.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(password: String, for robotId: UUID) -> Bool {
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: robotId.uuidString
        ]
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            logger.error("SecItemDelete (save) failed: \(deleteStatus, privacy: .public)")
        }

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: robotId.uuidString,
            kSecValueData: Data(password.utf8),
            kSecAttrAccessible: accessibility
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func delete(for robotId: UUID) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: robotId.uuidString
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            logger.error("SecItemDelete (delete) failed: \(deleteStatus, privacy: .public)")
        }
    }

    // MARK: - Accessibility

    /// Hebt Einträge älterer Versionen auf die Klasse, die auch bei gesperrtem Gerät lesbar ist.
    static func migrateAccessibility(for robotId: UUID) {
        for itemService in [service, configService] {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: itemService,
                kSecAttrAccount: robotId.uuidString
            ]
            let update: [CFString: Any] = [kSecAttrAccessible: accessibility]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                logger.error("SecItemUpdate (accessibility) failed: \(status, privacy: .public)")
            }
        }
    }

    static func passwordAccessibility(for robotId: UUID) -> String? {
        accessibilityValue(service: service, robotId: robotId)
    }

    static func configAccessibility(for robotId: UUID) -> String? {
        accessibilityValue(service: configService, robotId: robotId)
    }

    private static func accessibilityValue(service itemService: String, robotId: UUID) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: itemService,
            kSecAttrAccount: robotId.uuidString,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any] else { return nil }
        return attributes[kSecAttrAccessible as String] as? String
    }

    // MARK: - Robot Config Storage
    private static let configService = "com.valetudio.robot.config"

    static func robotConfig(for robotId: UUID) -> RobotConfig? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: configService,
            kSecAttrAccount: robotId.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("SecItemCopyMatching (robotConfig) failed: \(status, privacy: .public)")
            }
            return nil
        }
        do {
            return try JSONDecoder().decode(RobotConfig.self, from: data)
        } catch {
            logger.error("Failed to decode robot config: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    static func saveRobotConfig(_ config: RobotConfig, for robotId: UUID) -> Bool {
        // Delete-then-add pattern (identisch zum bestehenden Password-Pattern)
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: configService,
            kSecAttrAccount: robotId.uuidString
        ]
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            logger.error("SecItemDelete (saveRobotConfig) failed: \(deleteStatus, privacy: .public)")
        }

        guard let data = try? JSONEncoder().encode(config) else {
            logger.error("Failed to encode robot config for \(robotId.uuidString, privacy: .public)")
            return false
        }
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: configService,
            kSecAttrAccount: robotId.uuidString,
            kSecValueData: data,
            kSecAttrAccessible: accessibility
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logger.error("SecItemAdd (saveRobotConfig) failed: \(addStatus, privacy: .public)")
        }
        return addStatus == errSecSuccess
    }

    static func deleteRobotConfig(for robotId: UUID) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: configService,
            kSecAttrAccount: robotId.uuidString
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            logger.error("SecItemDelete (deleteRobotConfig) failed: \(deleteStatus, privacy: .public)")
        }
    }
}
