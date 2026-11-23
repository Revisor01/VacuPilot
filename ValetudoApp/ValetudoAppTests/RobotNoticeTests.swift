import XCTest
@testable import ValetudoApp

final class RobotNoticeTests: XCTestCase {

    private func consumable(_ type: String, percent: Int) throws -> Consumable {
        let json = #"{"type":"\#(type)","subType":null,"remaining":{"value":\#(percent),"unit":"percent"}}"#
        return try JSONDecoder().decode(Consumable.self, from: Data(json.utf8))
    }

    private func event(id: String, cls: String, processed: Bool, message: String? = nil) throws -> ValetudoEvent {
        let messageJSON = message.map { #""message":"\#($0)","# } ?? ""
        let json = #"{"__class":"\#(cls)","id":"\#(id)","timestamp":"2026-11-23T09:54:00.000Z","processed":\#(processed),\#(messageJSON)"type":null}"#
        return try JSONDecoder().decode(ValetudoEvent.self, from: Data(json.utf8))
    }

    // MARK: - Collecting

    func testNothingToReportIsEmpty() throws {
        let notices = RobotNotice.collect(
            error: nil,
            consumables: [try consumable("filter", percent: 80)],
            dockComponents: [DockComponent(type: "water_tank_clean", value: "ok")],
            events: [try event(id: "e1", cls: "DustBinFullValetudoEvent", processed: true)],
            pendingUpdate: nil
        )
        XCTAssertEqual(notices, [])
    }

    func testKindsAndOrderErrorWarningUpdate() throws {
        let notices = RobotNotice.collect(
            error: RobotErrorInfo(message: "LDS jammed"),
            consumables: [try consumable("filter", percent: 12)],
            dockComponents: [DockComponent(type: "water_tank_clean", value: "empty")],
            events: [],
            pendingUpdate: "2026.11.0"
        )
        XCTAssertEqual(notices.map(\.kind), [.error, .warning, .warning, .update])
        XCTAssertEqual(notices.first?.id, "error_LDS jammed")
        XCTAssertEqual(notices.last?.id, "update_2026.11.0")
    }

    func testConsumableBelowThresholdOnly() throws {
        let notices = RobotNotice.collect(
            error: nil,
            consumables: [try consumable("filter", percent: 19), try consumable("brush", percent: 20)],
            dockComponents: [],
            events: [],
            pendingUpdate: nil
        )
        XCTAssertEqual(notices.map(\.id), ["consumable_filter_main"])
    }

    func testOnlyUnprocessedEventsAndErrorEventsAreRed() throws {
        let notices = RobotNotice.collect(
            error: nil,
            consumables: [],
            dockComponents: [],
            events: [
                try event(id: "a", cls: "ErrorStateValetudoEvent", processed: false, message: "LDS jammed"),
                try event(id: "b", cls: "DustBinFullValetudoEvent", processed: false),
                try event(id: "c", cls: "ErrorStateValetudoEvent", processed: true, message: "LDS jammed"),
            ],
            pendingUpdate: nil
        )
        XCTAssertEqual(notices.map(\.id), ["event_a", "event_b"])
        XCTAssertEqual(notices.map(\.kind), [.error, .warning])
    }

    func testDockComponentIdIncludesState() {
        let notices = RobotNotice.collect(
            error: nil,
            consumables: [],
            dockComponents: [DockComponent(type: "water_tank_dirty", value: "full")],
            events: [],
            pendingUpdate: nil
        )
        XCTAssertEqual(notices.map(\.id), ["dock_water_tank_dirty_full"])
    }

    func testWarningSeverityErrorIsOrange() {
        let error = RobotErrorInfo(severity: .init(kind: "transient", level: "warning"), message: "Wheel lost floor contact")
        let notices = RobotNotice.collect(error: error, consumables: [], dockComponents: [], events: [], pendingUpdate: nil)
        XCTAssertEqual(notices.map(\.kind), [.warning])
    }

    // MARK: - New indicator

    private func notice(_ id: String, _ kind: RobotNotice.Kind) -> RobotNotice {
        RobotNotice(id: id, kind: kind, icon: "bell", title: id, detail: nil, date: nil, source: .consumable)
    }

    func testIndicatorTakesMostUrgentUnseenKind() {
        let notices = [notice("u", .update), notice("w", .warning), notice("e", .error)]
        XCTAssertEqual(NoticeSeenStore.newestKind(of: notices, seen: []), .error)
        XCTAssertEqual(NoticeSeenStore.newestKind(of: notices, seen: ["e"]), .warning)
        XCTAssertEqual(NoticeSeenStore.newestKind(of: notices, seen: ["e", "w"]), .update)
        XCTAssertNil(NoticeSeenStore.newestKind(of: notices, seen: ["e", "w", "u"]))
    }

    func testSeenStoreRemembersAndForgetsResolvedNotices() {
        let defaults = UserDefaults(suiteName: "RobotNoticeTests")!
        defaults.removePersistentDomain(forName: "RobotNoticeTests")
        let store = NoticeSeenStore(robotId: UUID(), defaults: defaults)

        store.markSeen([notice("a", .warning), notice("b", .error)])
        XCTAssertEqual(store.seenIds, ["a", "b"])

        // "a" was resolved; if it comes back later it must count as new.
        store.markSeen([notice("b", .error)])
        XCTAssertEqual(store.seenIds, ["b"])
        XCTAssertEqual(NoticeSeenStore.newestKind(of: [notice("a", .warning), notice("b", .error)], seen: store.seenIds), .warning)

        store.clear()
        XCTAssertEqual(store.seenIds, [])
    }

    func testIndicatorColors() {
        XCTAssertEqual(RobotNotice.Kind.error.color, .red)
        XCTAssertEqual(RobotNotice.Kind.warning.color, .orange)
        XCTAssertEqual(RobotNotice.Kind.update.color, .blue)
    }
}
