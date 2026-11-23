import XCTest
@testable import ValetudoApp

final class RobotErrorTests: XCTestCase {

    // MARK: - Helpers

    private let ldsJammed = RobotErrorInfo(
        severity: .init(kind: "permanent", level: "error"),
        subsystem: "sensors",
        message: "LDS jammed",
        vendorErrorCode: "1"
    )

    private let wheelLostContact = RobotErrorInfo(
        severity: .init(kind: "transient", level: "error"),
        subsystem: "core",
        message: "Wheel lost floor contact",
        vendorErrorCode: "3"
    )

    // Roborock sends this while a poll lacks the error code.
    private let placeholder = RobotErrorInfo(
        severity: .init(kind: "unknown", level: "unknown"),
        subsystem: "unknown",
        message: "Unknown error undefined",
        vendorErrorCode: "unknown (undefined)"
    )

    private func status(_ value: String, error: RobotErrorInfo? = nil, isOnline: Bool = true) -> RobotStatus {
        RobotStatus(isOnline: isOnline, attributes: [
            RobotAttribute(__class: "StatusStateAttribute", type: nil, subType: nil, value: value, level: nil, flag: "none", error: error)
        ])
    }

    private func errorEvents(_ events: [RobotStateEvent]) -> [RobotErrorInfo?] {
        events.compactMap { event -> RobotErrorInfo?? in
            if case .error(let error) = event { return .some(error) }
            return nil
        }
    }

    // MARK: - Decoding

    func testDecodesErrorObjectFromValetudoJSON() throws {
        let json = #"""
        {"__class":"StatusStateAttribute","metaData":{},"value":"error","flag":"none",
         "error":{"__class":"ValetudoRobotError","metaData":{},
                  "severity":{"kind":"permanent","level":"error"},
                  "subsystem":"sensors","message":"LDS jammed","vendorErrorCode":"1"}}
        """#
        let attribute = try JSONDecoder().decode(RobotAttribute.self, from: Data(json.utf8))

        XCTAssertEqual(attribute.value, "error")
        XCTAssertEqual(attribute.error, ldsJammed)
        XCTAssertEqual(RobotStatus(isOnline: true, attributes: [attribute]).robotError?.message, "LDS jammed")
    }

    func testAttributeWithoutErrorObjectStillDecodes() throws {
        let json = #"[{"__class":"StatusStateAttribute","value":"error","flag":"none"},{"__class":"BatteryStateAttribute","level":42,"flag":"discharging"}]"#
        let attributes = try JSONDecoder().decode([RobotAttribute].self, from: Data(json.utf8))

        XCTAssertEqual(attributes.count, 2)
        XCTAssertNil(attributes[0].error)
        XCTAssertEqual(attributes[1].level, 42)
    }

    func testMalformedErrorObjectDoesNotDropTheAttributeList() throws {
        let json = #"[{"__class":"StatusStateAttribute","value":"error","flag":"none","error":"broken"},{"__class":"BatteryStateAttribute","level":80}]"#
        let attributes = try JSONDecoder().decode([RobotAttribute].self, from: Data(json.utf8))

        XCTAssertEqual(attributes.count, 2)
        XCTAssertEqual(attributes[0].value, "error")
        XCTAssertNil(attributes[0].error)
    }

    func testPartialErrorObjectKeepsKnownFields() throws {
        let json = #"{"message":"Main brush jammed","severity":"odd"}"#
        let error = try JSONDecoder().decode(RobotErrorInfo.self, from: Data(json.utf8))

        XCTAssertEqual(error.message, "Main brush jammed")
        XCTAssertNil(error.severity)
        XCTAssertEqual(error.severityLevel, .unknown)
        XCTAssertEqual(error.knownKind, .mainBrushJammed)
    }

    // MARK: - Placeholder and vendor codes

    func testUnknownErrorUndefinedIsAPlaceholder() {
        XCTAssertTrue(placeholder.isPlaceholder)
        XCTAssertTrue(RobotErrorInfo(message: "").isPlaceholder)
        XCTAssertTrue(RobotErrorInfo().isPlaceholder)
        XCTAssertFalse(ldsJammed.isPlaceholder)
    }

    func testUnknownErrorWithNumericCodeIsNoPlaceholder() {
        let error = RobotErrorInfo(severity: .init(kind: "unknown", level: "unknown"), subsystem: "unknown",
                                   message: "Unknown error 254", vendorErrorCode: "254")

        XCTAssertFalse(error.isPlaceholder)
        XCTAssertEqual(error.numericVendorCode, "254")
        XCTAssertNil(error.knownKind)
        XCTAssertEqual(error.explanation.title, RobotErrorSubsystem.unknown.title)
        XCTAssertTrue(error.explanation.detail?.contains("254") == true)
        XCTAssertFalse(error.explanation.detail?.contains("Unknown error") == true)
    }

    func testPlaceholderExplanationHidesTheRawText() {
        let explanation = placeholder.explanation

        XCTAssertNil(explanation.detail)
        XCTAssertEqual(explanation.title, RobotErrorText.localized("robot_error.unknown.title"))
        XCTAssertFalse(explanation.title.contains("undefined"))
        XCTAssertFalse(explanation.help.contains("undefined"))
    }

    // MARK: - Message mapping

    func testKnownMessagesMapToKinds() {
        XCTAssertEqual(RobotErrorKind(message: "LDS jammed"), .ldsJammed)
        XCTAssertEqual(RobotErrorKind(message: "  lds JAMMED "), .ldsJammed)
        XCTAssertEqual(RobotErrorKind(message: "Wheel lost floor contact"), .wheelLostFloorContact)
        XCTAssertEqual(RobotErrorKind(message: "Mop Dock Wastewater Tank not installed or full"), .wastewaterTank)
        XCTAssertEqual(RobotErrorKind(message: "Side brush error. Reboot required"), .rebootRequired)
        XCTAssertNil(RobotErrorKind(message: "Flux capacitor overloaded"))
        XCTAssertNil(RobotErrorKind(message: nil))
    }

    func testKnownErrorUsesKindTextAndKeepsOriginalAsDetail() {
        let explanation = ldsJammed.explanation

        XCTAssertEqual(explanation.title, RobotErrorKind.ldsJammed.title)
        XCTAssertEqual(explanation.help, RobotErrorKind.ldsJammed.help)
        XCTAssertTrue(explanation.detail?.hasSuffix("LDS jammed") == true)
    }

    func testUnmappedMessageFallsBackToSubsystem() {
        let error = RobotErrorInfo(severity: .init(kind: "permanent", level: "error"), subsystem: "motors",
                                   message: "Mop motor current abnormal")

        XCTAssertEqual(error.explanation.title, RobotErrorSubsystem.motors.title)
        XCTAssertTrue(error.explanation.detail?.hasSuffix("Mop motor current abnormal") == true)
    }

    func testSeverityLevelParsing() {
        XCTAssertEqual(ldsJammed.severityLevel, .error)
        XCTAssertEqual(RobotErrorInfo(severity: .init(kind: "transient", level: "warning")).severityLevel, .warning)
        XCTAssertEqual(RobotErrorInfo(severity: .init(kind: "permanent", level: "catastrophic")).severityLevel, .catastrophic)
        XCTAssertEqual(RobotErrorInfo().severityLevel, .unknown)
    }

    // MARK: - Localization

    private func bundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), "\(language).lproj missing")
        return try XCTUnwrap(Bundle(path: path))
    }

    private var allKeys: [String] {
        RobotErrorKind.allCases.flatMap { ["robot_error.\($0.rawValue).title", "robot_error.\($0.rawValue).help"] }
            + RobotErrorSubsystem.allCases.flatMap { ["robot_error.subsystem.\($0.rawValue).title", "robot_error.subsystem.\($0.rawValue).help"] }
            + ["robot_error.unknown.title", "robot_error.placeholder.help", "robot_error.original %@", "robot_error.vendor_code %@"]
    }

    func testEveryErrorTextIsTranslated() throws {
        for language in ["de", "en", "fr"] {
            let bundle = try bundle(for: language)
            for key in allKeys {
                let value = bundle.localizedString(forKey: key, value: "\u{0}missing", table: nil)
                XCTAssertNotEqual(value, "\u{0}missing", "\(key) missing in \(language)")
                XCTAssertNotEqual(value, key, "\(key) untranslated in \(language)")
            }
        }
    }

    func testGermanTextForLdsJammed() throws {
        let bundle = try bundle(for: "de")
        XCTAssertEqual(bundle.localizedString(forKey: "robot_error.lds_jammed.title", value: nil, table: nil), "Lasersensor blockiert")
        XCTAssertEqual(bundle.localizedString(forKey: "robot_error.unknown.title", value: nil, table: nil), "Unbekannter Fehler")
    }

    // MARK: - Notification text

    func testNotificationBodyIsSpelledOut() {
        let body = NotificationService.errorBody(for: ldsJammed)

        XCTAssertEqual(body, "\(RobotErrorKind.ldsJammed.title). \(RobotErrorKind.ldsJammed.help)")
        XCTAssertFalse(NotificationService.errorBody(for: placeholder).contains("undefined"))
        XCTAssertFalse(NotificationService.errorBody(for: nil).isEmpty)
    }

    // MARK: - Debounce and display

    func testMeasuredFlickerNotifiesOncePerFault() {
        // Sequence as recorded from a Roborock S5 Max: fault, placeholder, fault, paused, resumed, fault again, then a new fault.
        let tracker = RobotStateTracker()
        let id = UUID()
        let start = Date()
        let sequence: [(TimeInterval, RobotStatus)] = [
            (0, status("cleaning")),
            (1, status("error", error: ldsJammed)),
            (1.1, status("error", error: placeholder)),
            (1.2, status("error", error: ldsJammed)),
            (1.3, status("error", error: placeholder)),
            (262, status("paused")),
            (270, status("cleaning")),
            (303, status("error", error: placeholder)),
            (303.1, status("error", error: ldsJammed)),
            (349, status("error", error: ldsJammed)),
            (937, status("paused")),
            (961, status("cleaning")),
            (978, status("error", error: wheelLostContact)),
            (978.1, status("error", error: placeholder)),
            (984, status("paused"))
        ]

        let events = sequence.flatMap { offset, state in
            tracker.apply(state, for: id, at: start.addingTimeInterval(offset))
        }

        XCTAssertEqual(errorEvents(events), [ldsJammed, wheelLostContact])
    }

    func testPlaceholderIsReplacedByLastSpecificFaultForDisplay() {
        let tracker = RobotStateTracker()
        let id = UUID()
        let now = Date()

        _ = tracker.apply(status("cleaning"), for: id, at: now)
        _ = tracker.apply(status("error", error: ldsJammed), for: id, at: now)
        _ = tracker.apply(status("error", error: placeholder), for: id, at: now.addingTimeInterval(0.1))

        XCTAssertEqual(tracker.displayedError(for: id), ldsJammed)

        _ = tracker.apply(status("docked"), for: id, at: now.addingTimeInterval(60))
        XCTAssertNil(tracker.displayedError(for: id))
    }

    func testSpecificFaultAfterPlaceholderUpgradesTheNotificationOnce() {
        let tracker = RobotStateTracker()
        let id = UUID()
        let now = Date()

        _ = tracker.apply(status("cleaning"), for: id, at: now)
        let first = tracker.apply(status("error", error: placeholder), for: id, at: now)
        let second = tracker.apply(status("error", error: ldsJammed), for: id, at: now.addingTimeInterval(0.1))
        let third = tracker.apply(status("error", error: placeholder), for: id, at: now.addingTimeInterval(0.2))

        XCTAssertEqual(errorEvents(first), [placeholder])
        XCTAssertEqual(errorEvents(second), [ldsJammed])
        XCTAssertEqual(errorEvents(third), [])
    }

    func testSameFaultNotifiesAgainAfterTheWindow() {
        let tracker = RobotStateTracker()
        let id = UUID()
        let now = Date()
        let later = now.addingTimeInterval(RobotStateTracker.errorMemoryWindow + 60)

        _ = tracker.apply(status("cleaning"), for: id, at: now)
        let first = tracker.apply(status("error", error: ldsJammed), for: id, at: now)
        _ = tracker.apply(status("docked"), for: id, at: now.addingTimeInterval(30))
        _ = tracker.apply(status("cleaning"), for: id, at: later.addingTimeInterval(-10))
        let second = tracker.apply(status("error", error: ldsJammed), for: id, at: later)

        XCTAssertEqual(errorEvents(first), [ldsJammed])
        XCTAssertEqual(errorEvents(second), [ldsJammed])
    }

    func testFaultAtAppStartIsShownButNotAnnounced() {
        let tracker = RobotStateTracker()
        let id = UUID()

        let events = tracker.apply(status("error", error: ldsJammed), for: id)

        XCTAssertEqual(errorEvents(events), [])
        XCTAssertEqual(tracker.displayedError(for: id), ldsJammed)
    }

    func testFirmwareWithoutErrorObjectNotifiesOnceWithoutDetails() {
        let tracker = RobotStateTracker()
        let id = UUID()
        let now = Date()

        _ = tracker.apply(status("cleaning"), for: id, at: now)
        let first = tracker.apply(status("error"), for: id, at: now)
        _ = tracker.apply(status("paused"), for: id, at: now.addingTimeInterval(5))
        let second = tracker.apply(status("error"), for: id, at: now.addingTimeInterval(40))

        XCTAssertEqual(errorEvents(first), [nil])
        XCTAssertEqual(errorEvents(second), [])
        XCTAssertNil(tracker.displayedError(for: id))
    }

    func testForgetClearsErrorMemory() {
        let tracker = RobotStateTracker()
        let id = UUID()

        _ = tracker.apply(status("error", error: ldsJammed), for: id)
        tracker.forget(id)

        XCTAssertNil(tracker.displayedError(for: id))
    }
}
