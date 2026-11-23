import XCTest
@testable import ValetudoApp

final class RobotConfigStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "RobotConfigStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func storeIDs(_ ids: [UUID]) throws {
        defaults.set(try JSONEncoder().encode(ids), forKey: RobotConfigStore.idsKey)
    }

    // State after the app moved robots to the Keychain: ID list only, legacy list deleted.
    func testBackgroundCheckFindsRobotsSavedByTheApp() throws {
        let staubi = RobotConfig(name: "Staubi", host: "robot-a.local")
        let wischi = RobotConfig(name: "Wischi", host: "robot-b.local")
        let keychain = [staubi.id: staubi, wischi.id: wischi]
        try storeIDs([staubi.id, wischi.id])

        let robots = RobotConfigStore.robotsForBackgroundCheck(defaults: defaults, loadConfig: { keychain[$0] })

        XCTAssertNil(defaults.data(forKey: RobotConfigStore.legacyKey))
        XCTAssertEqual(robots, [staubi, wischi])
    }

    func testBackgroundCheckReadsLegacyListBeforeMigration() throws {
        let legacy = RobotConfig(name: "Alt", host: "robot-c.local")
        defaults.set(try JSONEncoder().encode([legacy]), forKey: RobotConfigStore.legacyKey)

        let robots = RobotConfigStore.robotsForBackgroundCheck(defaults: defaults, loadConfig: { _ in nil })

        XCTAssertEqual(robots.map(\.id), [legacy.id])
        XCTAssertNotNil(defaults.data(forKey: RobotConfigStore.legacyKey), "background check must not migrate")
    }

    func testIDsWithoutKeychainEntryAreSkipped() throws {
        let staubi = RobotConfig(name: "Staubi", host: "robot-a.local")
        try storeIDs([UUID(), staubi.id])

        let robots = RobotConfigStore.savedRobots(defaults: defaults, loadConfig: { $0 == staubi.id ? staubi : nil })

        XCTAssertEqual(robots, [staubi])
    }

    func testNothingSavedReturnsEmptyList() {
        XCTAssertEqual(RobotConfigStore.robotsForBackgroundCheck(defaults: defaults, loadConfig: { _ in nil }), [])
    }
}
