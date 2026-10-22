import XCTest
@testable import ValetudoApp

final class ConsumableTests: XCTestCase {

    // MARK: - Helpers

    private func makeConsumable(type: String, subType: String? = nil, value: Int, unit: String) -> Consumable {
        let remaining = ConsumableRemaining(value: value, unit: unit)
        return Consumable(__class: nil, type: type, subType: subType, remaining: remaining)
    }

    // MARK: - remainingPercent

    func testRemainingPercentWithPercentUnit() {
        let consumable = makeConsumable(type: "brush", subType: "main", value: 75, unit: "percent")
        XCTAssertEqual(consumable.remainingPercent, 75.0, accuracy: 0.001)
    }

    func testRemainingPercentWithMinutesMainBrush() {
        // maxMinutes for main brush = 18000
        let consumable = makeConsumable(type: "brush", subType: "main", value: 9000, unit: "minutes")
        XCTAssertEqual(consumable.remainingPercent, 50.0, accuracy: 0.001)
    }

    func testRemainingPercentWithMinutesSideBrush() {
        // maxMinutes for side brush = 12000
        let consumable = makeConsumable(type: "brush", subType: "side_right", value: 6000, unit: "minutes")
        XCTAssertEqual(consumable.remainingPercent, 50.0, accuracy: 0.001)
    }

    func testRemainingPercentCapsAt100() {
        // 20000 minutes > 18000 max, should be capped at 100
        let consumable = makeConsumable(type: "brush", subType: "main", value: 20000, unit: "minutes")
        XCTAssertEqual(consumable.remainingPercent, 100.0, accuracy: 0.001)
    }

    func testRemainingPercentFilter() {
        // maxMinutes for filter = 9000
        let consumable = makeConsumable(type: "filter", value: 4500, unit: "minutes")
        XCTAssertEqual(consumable.remainingPercent, 50.0, accuracy: 0.001)
    }

    func testRemainingPercentZero() {
        let consumable = makeConsumable(type: "brush", subType: "main", value: 0, unit: "percent")
        XCTAssertEqual(consumable.remainingPercent, 0.0, accuracy: 0.001)
    }

    func testRemainingPercentFullPercent() {
        let consumable = makeConsumable(type: "filter", value: 100, unit: "percent")
        XCTAssertEqual(consumable.remainingPercent, 100.0, accuracy: 0.001)
    }

    // MARK: - iconColor

    func testIconColorGreen() {
        let consumable = makeConsumable(type: "brush", subType: "main", value: 75, unit: "percent")
        XCTAssertEqual(consumable.iconColor, .green)
    }

    func testIconColorOrange() {
        let consumable = makeConsumable(type: "brush", subType: "main", value: 35, unit: "percent")
        XCTAssertEqual(consumable.iconColor, .orange)
    }

    func testIconColorOrangeLowerBound() {
        let consumable = makeConsumable(type: "brush", subType: "main", value: 21, unit: "percent")
        XCTAssertEqual(consumable.iconColor, .orange)
    }

    func testIconColorRed() {
        let consumable = makeConsumable(type: "brush", subType: "main", value: 15, unit: "percent")
        XCTAssertEqual(consumable.iconColor, .red)
    }

    func testIconColorRedAtZero() {
        let consumable = makeConsumable(type: "filter", value: 0, unit: "percent")
        XCTAssertEqual(consumable.iconColor, .red)
    }

    // MARK: - displayName (Firmware 2026.10.0: Walzenmopp-Auflockerer als brush/secondary)

    func testDisplayNameSecondaryBrushIsLocalized() {
        let consumable = makeConsumable(type: "brush", subType: "secondary", value: 600, unit: "minutes")
        let expected = "\(String(localized: "consumable.brush")) (\(String(localized: "consumable.secondary")))"
        XCTAssertEqual(consumable.displayName, expected)
        XCTAssertFalse(consumable.displayName.contains("consumable."), "Übersetzung fehlt")
    }

    func testDisplayNameHidesSubTypeAll() {
        let consumable = makeConsumable(type: "filter", subType: "all", value: 50, unit: "percent")
        XCTAssertEqual(consumable.displayName, String(localized: "consumable.filter"))
    }

    func testDisplayNameDetergentIsLocalized() {
        let consumable = makeConsumable(type: "detergent", subType: "dock", value: 50, unit: "percent")
        let expected = "\(String(localized: "consumable.detergent")) (\(String(localized: "consumable.dock")))"
        XCTAssertEqual(consumable.displayName, expected)
        XCTAssertFalse(consumable.displayName.contains("consumable."), "Übersetzung fehlt")
    }
}

/// Trockenzeit-Werte der Mopp-Station. 2026.10.0 bringt "5h" und "quiet" dazu;
/// vorher wurde "5h" zu "5H" und "quiet" blieb unübersetzt.
final class DryingTimeDisplayNameTests: XCTestCase {

    func testFiveHoursIsLocalized() {
        let name = StationSettingsView.displayNameForDryingTime("5h")
        XCTAssertEqual(name, String(localized: "drying_time.5h"))
        XCTAssertNotEqual(name, "drying_time.5h", "Übersetzung fehlt")
        XCTAssertNotEqual(name, "5H")
    }

    func testQuietIsLocalized() {
        let name = StationSettingsView.displayNameForDryingTime("quiet")
        XCTAssertEqual(name, String(localized: "drying_time.quiet"))
        XCTAssertNotEqual(name, "drying_time.quiet", "Übersetzung fehlt")
    }

    func testKnownValuesUnchanged() {
        XCTAssertEqual(StationSettingsView.displayNameForDryingTime("2h"), String(localized: "drying_time.2h"))
        XCTAssertEqual(StationSettingsView.displayNameForDryingTime("cold"), String(localized: "drying_time.cold"))
    }

    func testUnknownHourValueStaysReadable() {
        XCTAssertEqual(StationSettingsView.displayNameForDryingTime("6h"), "6 h")
    }

    func testUnknownWordValueIsHumanized() {
        XCTAssertEqual(StationSettingsView.displayNameForDryingTime("extra_long"), "Extra Long")
    }
}
