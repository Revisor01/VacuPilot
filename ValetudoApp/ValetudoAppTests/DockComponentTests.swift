import XCTest
@testable import ValetudoApp

final class DockComponentTests: XCTestCase {

    // MARK: - Helpers

    private func dockAttribute(_ type: String, _ value: String) -> RobotAttribute {
        RobotAttribute(__class: "DockComponentStateAttribute", type: type, subType: nil, value: value, level: nil, flag: nil)
    }

    private func status(_ attributes: [RobotAttribute], isOnline: Bool = true) -> RobotStatus {
        RobotStatus(isOnline: isOnline, attributes: attributes)
    }

    // MARK: - Decoding

    func testDecodesDockComponentAttributeFromValetudoJSON() throws {
        let json = """
        [
          {"__class": "DockComponentStateAttribute", "metaData": {}, "type": "detergent", "value": "empty"},
          {"__class": "DockComponentStateAttribute", "metaData": {}, "type": "dustbag", "value": "ok"}
        ]
        """.data(using: .utf8)!
        let attributes = try JSONDecoder().decode([RobotAttribute].self, from: json)

        let components = status(attributes).dockComponents

        XCTAssertEqual(components, [
            DockComponent(type: "detergent", value: "empty"),
            DockComponent(type: "dustbag", value: "ok")
        ])
    }

    // MARK: - dockComponents

    func testDockComponentsInValetudoOrder() {
        let attrs = [
            dockAttribute("dustbag", "ok"),
            dockAttribute("detergent", "empty"),
            dockAttribute("water_tank_dirty", "ok"),
            dockAttribute("water_tank_clean", "ok")
        ]

        XCTAssertEqual(status(attrs).dockComponents.map(\.type),
                       ["water_tank_clean", "water_tank_dirty", "detergent", "dustbag"])
    }

    func testDockComponentsIgnoreOtherAttributes() {
        let attrs = [
            RobotAttribute(__class: "AttachmentStateAttribute", type: "mop", subType: nil, value: "true", level: nil, flag: nil),
            RobotAttribute(__class: "BatteryStateAttribute", type: nil, subType: nil, value: nil, level: 80, flag: "charged")
        ]

        XCTAssertEqual(status(attrs).dockComponents, [])
    }

    func testDockComponentWithoutValueIsUnknown() {
        let attr = RobotAttribute(__class: "DockComponentStateAttribute", type: "detergent", subType: nil, value: nil, level: nil, flag: nil)

        XCTAssertEqual(status([attr]).dockComponents, [DockComponent(type: "detergent", value: "unknown")])
    }

    // MARK: - needsAttention

    func testNeedsAttention() {
        XCTAssertTrue(DockComponent(type: "detergent", value: "empty").needsAttention)
        XCTAssertTrue(DockComponent(type: "detergent", value: "missing").needsAttention)
        XCTAssertTrue(DockComponent(type: "water_tank_dirty", value: "full").needsAttention)
        XCTAssertFalse(DockComponent(type: "detergent", value: "ok").needsAttention)
        XCTAssertFalse(DockComponent(type: "detergent", value: "unknown").needsAttention)
    }

    // MARK: - newDockComponentProblems

    func testDetergentRunningEmptyIsReported() {
        let before = status([dockAttribute("detergent", "ok"), dockAttribute("dustbag", "ok")])
        let after = status([dockAttribute("detergent", "empty"), dockAttribute("dustbag", "ok")])

        XCTAssertEqual(after.newDockComponentProblems(since: before), [DockComponent(type: "detergent", value: "empty")])
    }

    func testProblemThatPersistsIsNotReportedAgain() {
        let before = status([dockAttribute("detergent", "empty")])
        let after = status([dockAttribute("detergent", "empty")])

        XCTAssertEqual(after.newDockComponentProblems(since: before), [])
    }

    func testChangeFromEmptyToMissingIsReported() {
        let before = status([dockAttribute("detergent", "empty")])
        let after = status([dockAttribute("detergent", "missing")])

        XCTAssertEqual(after.newDockComponentProblems(since: before), [DockComponent(type: "detergent", value: "missing")])
    }

    func testNothingReportedWithoutPreviousStatus() {
        let after = status([dockAttribute("detergent", "empty")])

        XCTAssertEqual(after.newDockComponentProblems(since: nil), [])
    }

    func testNothingReportedWhenComingBackOnline() {
        let before = status([], isOnline: false)
        let after = status([dockAttribute("detergent", "empty")])

        XCTAssertEqual(after.newDockComponentProblems(since: before), [])
    }

    func testRefilledComponentIsNotReported() {
        let before = status([dockAttribute("detergent", "empty")])
        let after = status([dockAttribute("detergent", "ok")])

        XCTAssertEqual(after.newDockComponentProblems(since: before), [])
    }
}
