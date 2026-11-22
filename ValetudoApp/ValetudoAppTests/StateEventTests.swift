import XCTest
@testable import ValetudoApp

final class StateEventTests: XCTestCase {

    private func status(_ value: String, flag: String? = nil, isOnline: Bool = true) -> RobotStatus {
        RobotStatus(isOnline: isOnline, attributes: [
            RobotAttribute(__class: "StatusStateAttribute", type: nil, subType: nil, value: value, level: nil, flag: flag)
        ])
    }

    func testCleaningToDockedReportsCompletion() {
        XCTAssertEqual(status("docked").stateEvents(since: status("cleaning")), [.cleaningComplete(area: nil)])
    }

    func testDockedToDockedReportsNothing() {
        XCTAssertEqual(status("docked").stateEvents(since: status("docked")), [])
    }

    func testWithoutPreviousStatusNothingIsReported() {
        XCTAssertEqual(status("error").stateEvents(since: nil), [])
        XCTAssertEqual(status("docked").stateEvents(since: RobotStatus(isOnline: false)), [])
    }

    func testStuckAndErrorOnlyOnEntry() {
        XCTAssertEqual(status("error", flag: "stuck").stateEvents(since: status("cleaning")), [.stuck, .error("stuck")])
        XCTAssertEqual(status("error", flag: "stuck").stateEvents(since: status("error", flag: "stuck")), [])
    }

    func testRepeatedUpdatesReportCompletionOnce() {
        let tracker = RobotStateTracker()
        let id = UUID()
        let events = ["cleaning", "docked", "docked", "docked"].flatMap { tracker.apply(status($0), for: id) }
        XCTAssertEqual(events, [.cleaningComplete(area: nil)])
    }

    func testTrackerKeepsRobotsApart() {
        let tracker = RobotStateTracker()
        let a = UUID(), b = UUID()
        XCTAssertEqual(tracker.apply(status("cleaning"), for: a), [])
        XCTAssertEqual(tracker.apply(status("docked"), for: b), [])
        XCTAssertEqual(tracker.apply(status("docked"), for: a), [.cleaningComplete(area: nil)])
    }
}
