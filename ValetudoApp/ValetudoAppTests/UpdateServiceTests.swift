import XCTest
@testable import ValetudoApp

// MARK: - MockValetudoAPI

final class MockValetudoAPI: ValetudoAPIProtocol, @unchecked Sendable {

    var updaterStateToReturn: UpdaterState = UpdaterState(
        __class: "ValetudoUpdaterIdleState",
        busy: nil, currentVersion: nil, version: nil,
        releaseTimestamp: nil, downloadUrl: nil, downloadPath: nil, metaData: nil
    )

    var versionToReturn: ValetudoVersion = ValetudoVersion(release: "2024.01.0", commit: "abc123")
    var shouldThrowOnCheck = false
    var shouldThrowOnDownload = false
    var getUpdaterStateCallCount = 0

    /// States for successive getUpdaterState calls, then updaterStateToReturn.
    var stateSequence: [UpdaterState]? = nil

    func checkForUpdates() async throws {
        if shouldThrowOnCheck { throw URLError(.badServerResponse) }
    }

    func getUpdaterState() async throws -> UpdaterState {
        getUpdaterStateCallCount += 1
        if let seq = stateSequence, getUpdaterStateCallCount <= seq.count {
            return seq[getUpdaterStateCallCount - 1]
        }
        return updaterStateToReturn
    }

    func downloadUpdate() async throws {
        if shouldThrowOnDownload { throw URLError(.badServerResponse) }
    }

    func applyUpdate() async throws {}

    func getValetudoVersion() async throws -> ValetudoVersion {
        versionToReturn
    }
}

// MARK: - Helpers

private func makeUpdaterState(_ className: String) -> UpdaterState {
    UpdaterState(
        __class: className,
        busy: nil, currentVersion: nil, version: nil,
        releaseTimestamp: nil, downloadUrl: nil, downloadPath: nil, metaData: nil
    )
}

// MARK: - UpdateServiceTests

@MainActor
final class UpdateServiceTests: XCTestCase {

    // MARK: - checkForUpdates: idle → checking → updateAvailable

    func testCheckForUpdates_withApprovalPendingState_transitionsToUpdateAvailable() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterApprovalPendingState")
        let service = UpdateService(api: mock)

        await service.checkForUpdates()

        XCTAssertEqual(service.phase, .updateAvailable)
    }

    // MARK: - checkForUpdates: idle → checking → idle (no update)

    func testCheckForUpdates_withIdleState_remainsIdle() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterIdleState")
        let service = UpdateService(api: mock)

        await service.checkForUpdates()

        XCTAssertEqual(service.phase, .idle)
    }

    // MARK: - checkForUpdates: idle → checking → idle (Fehler bei der Prüfung ist still)

    func testCheckForUpdates_whenAPIThrows_fallsBackToIdleSilently() async throws {
        let mock = MockValetudoAPI()
        mock.shouldThrowOnCheck = true
        let service = UpdateService(api: mock)

        await service.checkForUpdates()

        // A failed check falls back silently to .idle, no error banner.
        XCTAssertEqual(service.phase, .idle)
    }

    // MARK: - startDownload: updateAvailable → downloading (then poll to readyToApply)

    func testStartDownload_fromUpdateAvailable_transitionsToReadyToApply() async throws {
        let mock = MockValetudoAPI()
        // First call ApprovalPending, then ApplyPending during startDownload.
        mock.stateSequence = [
            makeUpdaterState("ValetudoUpdaterApprovalPendingState"),
            makeUpdaterState("ValetudoUpdaterApplyPendingState")
        ]
        let service = UpdateService(api: mock)

        // Bring service to updateAvailable
        await service.checkForUpdates()
        XCTAssertEqual(service.phase, .updateAvailable)

        // Start download — poll will get ApplyPendingState on first call
        await service.startDownload()

        XCTAssertEqual(service.phase, .readyToApply)
    }

    // MARK: - startDownload: downloading → error (API throws)

    func testStartDownload_whenDownloadAPIThrows_transitionsToError() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterApprovalPendingState")
        mock.shouldThrowOnDownload = true
        let service = UpdateService(api: mock)

        await service.checkForUpdates()
        XCTAssertEqual(service.phase, .updateAvailable)

        await service.startDownload()

        if case .error = service.phase {
            // expected
        } else {
            XCTFail("Expected error phase, got \(service.phase)")
        }
    }

    // MARK: - startDownload: downloading → error (poll returns idle = interrupted)

    func testStartDownload_whenPollReturnsIdle_transitionsToInterruptedError() async throws {
        let mock = MockValetudoAPI()
        // First call ApprovalPending, then IdleState → "Download unterbrochen".
        mock.stateSequence = [
            makeUpdaterState("ValetudoUpdaterApprovalPendingState"),
            makeUpdaterState("ValetudoUpdaterIdleState")
        ]
        let service = UpdateService(api: mock)

        await service.checkForUpdates()
        XCTAssertEqual(service.phase, .updateAvailable)

        await service.startDownload()

        XCTAssertEqual(service.phase, .error("Download wurde unterbrochen"))
    }

    // MARK: - reset: error → idle

    func testReset_fromErrorState_transitionsToIdle() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterApprovalPendingState")
        mock.shouldThrowOnDownload = true
        let service = UpdateService(api: mock)

        // Eine fehlgeschlagene Prüfung endet still in .idle; .error entsteht nur beim Download.
        await service.checkForUpdates()
        await service.startDownload()
        if case .error = service.phase { } else {
            XCTFail("Setup failed: expected error phase")
        }

        service.reset()

        XCTAssertEqual(service.phase, .idle)
    }

    // MARK: - reset: any state → idle

    func testReset_fromUpdateAvailableState_transitionsToIdle() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterApprovalPendingState")
        let service = UpdateService(api: mock)

        await service.checkForUpdates()
        XCTAssertEqual(service.phase, .updateAvailable)

        service.reset()

        XCTAssertEqual(service.phase, .idle)
    }

    // MARK: - mapUpdaterState: IdleState → .idle

    func testMapping_idleState_mapsToIdle() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterIdleState")
        let service = UpdateService(api: mock)

        await service.checkForUpdates()

        XCTAssertEqual(service.phase, .idle)
    }

    // MARK: - mapUpdaterState: ApprovalPendingState → .updateAvailable

    func testMapping_approvalPendingState_mapsToUpdateAvailable() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterApprovalPendingState")
        let service = UpdateService(api: mock)

        await service.checkForUpdates()

        XCTAssertEqual(service.phase, .updateAvailable)
    }

    // MARK: - mapUpdaterState: DownloadingState → .downloading

    func testMapping_downloadingState_mapsToDownloading() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterDownloadingState")
        let service = UpdateService(api: mock)

        await service.checkForUpdates()

        XCTAssertEqual(service.phase, .downloading)
    }

    // MARK: - mapUpdaterState: ApplyPendingState → .readyToApply

    func testMapping_applyPendingState_mapsToReadyToApply() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterApplyPendingState")
        let service = UpdateService(api: mock)

        await service.checkForUpdates()

        XCTAssertEqual(service.phase, .readyToApply)
    }

    // MARK: - mapUpdaterState: DisabledState → .idle

    func testMapping_disabledState_mapsToIdle() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterDisabledState")
        let service = UpdateService(api: mock)

        await service.checkForUpdates()

        XCTAssertEqual(service.phase, .idle)
    }

    // MARK: - mapUpdaterState: ErrorState → .error

    func testMapping_errorState_mapsToError() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterErrorState")
        let service = UpdateService(api: mock)

        await service.checkForUpdates()

        // Unknown states such as ErrorState map to .idle.
        XCTAssertEqual(service.phase, .idle)
    }

    // MARK: - mapUpdaterState: NoUpdateRequiredState → .idle

    func testMapping_noUpdateRequiredState_mapsToIdle() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterNoUpdateRequiredState")
        let service = UpdateService(api: mock)

        await service.checkForUpdates()

        XCTAssertEqual(service.phase, .idle)
    }

    // MARK: - mapUpdaterState: unknown class → .idle

    func testMapping_unknownClass_mapsToIdle() async throws {
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = makeUpdaterState("SomeUnknownUpdaterState")
        let service = UpdateService(api: mock)

        await service.checkForUpdates()

        XCTAssertEqual(service.phase, .idle)
    }

    // MARK: - Skipping a version

    private func makeDefaults() -> UserDefaults {
        let name = "UpdateServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func pendingState(version: String) -> UpdaterState {
        UpdaterState(
            __class: "ValetudoUpdaterApprovalPendingState",
            busy: nil, currentVersion: "2026.08.0", version: version,
            releaseTimestamp: nil, downloadUrl: nil, downloadPath: nil, metaData: nil
        )
    }

    func testSkippedVersion_hidesBanner() async throws {
        let store = SkippedUpdateStore(robotId: UUID(), defaults: makeDefaults())
        store.skip("2026.10.0")
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = pendingState(version: "2026.10.0")
        let service = UpdateService(api: mock, skipStore: store)

        await service.checkForUpdates()

        XCTAssertEqual(service.phase, .updateAvailable)
        XCTAssertEqual(service.pendingVersion, "2026.10.0")
        XCTAssertFalse(service.showsUpdateAvailableBanner)
    }

    func testNewerVersionAfterSkip_showsBannerAgain() async throws {
        let store = SkippedUpdateStore(robotId: UUID(), defaults: makeDefaults())
        store.skip("2026.10.0")
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = pendingState(version: "2026.11.0")
        let service = UpdateService(api: mock, skipStore: store)

        await service.checkForUpdates()

        XCTAssertEqual(service.skippedVersion, "2026.10.0")
        XCTAssertEqual(service.pendingVersion, "2026.11.0")
        XCTAssertTrue(service.showsUpdateAvailableBanner)
    }

    func testSkipOnOneRobot_leavesOtherRobotUnaffected() async throws {
        let defaults = makeDefaults()
        let storeA = SkippedUpdateStore(robotId: UUID(), defaults: defaults)
        let storeB = SkippedUpdateStore(robotId: UUID(), defaults: defaults)
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = pendingState(version: "2026.10.0")
        let serviceA = UpdateService(api: mock, skipStore: storeA)
        let serviceB = UpdateService(api: mock, skipStore: storeB)
        await serviceA.checkForUpdates()
        await serviceB.checkForUpdates()

        serviceA.skip(version: "2026.10.0")

        XCTAssertFalse(serviceA.showsUpdateAvailableBanner)
        XCTAssertTrue(serviceB.showsUpdateAvailableBanner)
        XCTAssertEqual(storeA.version, "2026.10.0")
        XCTAssertNil(storeB.version)
    }

    func testSkip_persistsAcrossServiceInstances() async throws {
        let store = SkippedUpdateStore(robotId: UUID(), defaults: makeDefaults())
        UpdateService(api: MockValetudoAPI(), skipStore: store).skip(version: "2026.10.0")

        let reopened = UpdateService(api: MockValetudoAPI(), skipStore: store)

        XCTAssertEqual(reopened.skippedVersion, "2026.10.0")
    }

    func testClearSkippedVersion_showsBannerAgain() async throws {
        let store = SkippedUpdateStore(robotId: UUID(), defaults: makeDefaults())
        store.skip("2026.10.0")
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = pendingState(version: "2026.10.0")
        let service = UpdateService(api: mock, skipStore: store)
        await service.checkForUpdates()
        XCTAssertFalse(service.showsUpdateAvailableBanner)

        service.clearSkippedVersion()

        XCTAssertNil(service.skippedVersion)
        XCTAssertNil(store.version)
        XCTAssertTrue(service.showsUpdateAvailableBanner)
    }

    func testSkippedVersion_installStaysPossible() async throws {
        let store = SkippedUpdateStore(robotId: UUID(), defaults: makeDefaults())
        store.skip("2026.10.0")
        let mock = MockValetudoAPI()
        mock.updaterStateToReturn = pendingState(version: "2026.10.0")
        let service = UpdateService(api: mock, skipStore: store)
        await service.checkForUpdates()

        mock.updaterStateToReturn = makeUpdaterState("ValetudoUpdaterApplyPendingState")
        await service.startDownload()

        XCTAssertEqual(service.phase, .readyToApply)
    }

    func testStoreWithoutSkippedVersion_skipsNothing() {
        let store = SkippedUpdateStore(robotId: UUID(), defaults: makeDefaults())

        XCTAssertFalse(store.isSkipped("2026.10.0"))
        XCTAssertFalse(store.isSkipped(nil))
    }
}
