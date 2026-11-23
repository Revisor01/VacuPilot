import XCTest
@testable import ValetudoApp

final class EndpointSelectorTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Resolving

    func testWithoutRemoteNeverResolvesAndStaysHome() {
        var selector = EndpointSelector(hasRemote: false)
        XCTAssertFalse(selector.needsResolve(now: start, pathGeneration: 1))
        XCTAssertNil(selector.failover(from: .home, now: start, pathGeneration: 1))
        XCTAssertEqual(selector.active, .home)
    }

    func testFirstRequestResolves() {
        let selector = EndpointSelector(hasRemote: true)
        XCTAssertTrue(selector.needsResolve(now: start, pathGeneration: 1))
    }

    func testHomeReachableChoosesHome() {
        var selector = EndpointSelector(hasRemote: true)
        selector.resolve(homeReachable: true, now: start, pathGeneration: 1)
        XCTAssertEqual(selector.active, .home)
    }

    func testHomeUnreachableChoosesRemote() {
        var selector = EndpointSelector(hasRemote: true)
        selector.resolve(homeReachable: false, now: start, pathGeneration: 1)
        XCTAssertEqual(selector.active, .remote)
    }

    func testAtHomeNoRecheckUntilNetworkChanges() {
        var selector = EndpointSelector(hasRemote: true)
        selector.resolve(homeReachable: true, now: start, pathGeneration: 1)
        XCTAssertFalse(selector.needsResolve(now: start.addingTimeInterval(3600), pathGeneration: 1))
        XCTAssertTrue(selector.needsResolve(now: start.addingTimeInterval(1), pathGeneration: 2))
    }

    func testAwayRechecksHomeAfterInterval() {
        var selector = EndpointSelector(hasRemote: true)
        selector.resolve(homeReachable: false, now: start, pathGeneration: 1)
        XCTAssertFalse(selector.needsResolve(now: start.addingTimeInterval(59), pathGeneration: 1))
        XCTAssertTrue(selector.needsResolve(now: start.addingTimeInterval(60), pathGeneration: 1))
    }

    func testAwayRechecksImmediatelyAfterNetworkChange() {
        var selector = EndpointSelector(hasRemote: true)
        selector.resolve(homeReachable: false, now: start, pathGeneration: 1)
        XCTAssertTrue(selector.needsResolve(now: start.addingTimeInterval(1), pathGeneration: 2))
    }

    // MARK: - Failover

    func testFailoverFromHomeGoesRemote() {
        var selector = EndpointSelector(hasRemote: true)
        selector.resolve(homeReachable: true, now: start, pathGeneration: 1)
        XCTAssertEqual(selector.failover(from: .home, now: start, pathGeneration: 1), .remote)
        XCTAssertEqual(selector.active, .remote)
    }

    func testFailoverFromRemoteGoesHome() {
        var selector = EndpointSelector(hasRemote: true)
        selector.resolve(homeReachable: false, now: start, pathGeneration: 1)
        XCTAssertEqual(selector.failover(from: .remote, now: start, pathGeneration: 1), .home)
        XCTAssertEqual(selector.active, .home)
    }

    func testParallelFailuresDoNotFlipBack() {
        var selector = EndpointSelector(hasRemote: true)
        selector.resolve(homeReachable: true, now: start, pathGeneration: 1)
        // Two requests started on home both fail; the second must not switch back to home.
        XCTAssertEqual(selector.failover(from: .home, now: start, pathGeneration: 1), .remote)
        XCTAssertEqual(selector.failover(from: .home, now: start, pathGeneration: 1), .remote)
        XCTAssertEqual(selector.active, .remote)
    }

    func testFailoverCountsAsFreshChoice() {
        var selector = EndpointSelector(hasRemote: true)
        selector.resolve(homeReachable: true, now: start, pathGeneration: 1)
        _ = selector.failover(from: .home, now: start.addingTimeInterval(10), pathGeneration: 1)
        XCTAssertFalse(selector.needsResolve(now: start.addingTimeInterval(30), pathGeneration: 1))
        XCTAssertTrue(selector.needsResolve(now: start.addingTimeInterval(70), pathGeneration: 1))
    }

    // MARK: - Unreachable errors

    func testUnreachableErrors() {
        for code: URLError.Code in [.cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut,
                                    .notConnectedToInternet, .networkConnectionLost] {
            XCTAssertTrue(EndpointSelector.isUnreachable(URLError(code)), "\(code)")
        }
    }

    func testOtherErrorsDoNotSwitch() {
        XCTAssertFalse(EndpointSelector.isUnreachable(URLError(.cancelled)))
        XCTAssertFalse(EndpointSelector.isUnreachable(URLError(.serverCertificateUntrusted)))
        XCTAssertFalse(EndpointSelector.isUnreachable(APIError.httpError(401)))
        XCTAssertFalse(EndpointSelector.isUnreachable(APIError.httpError(503)))
        XCTAssertFalse(EndpointSelector.isUnreachable(CancellationError()))
    }

    // MARK: - RobotConfig remote address

    func testRemoteURLWithSchemeKeepsSchemeAndPort() {
        let url = RobotConfig.parseRemoteURL("http://robot.example.org:8080")
        XCTAssertEqual(url?.absoluteString, "http://robot.example.org:8080")
    }

    func testRemoteURLWithoutSchemeIsHTTPS() {
        XCTAssertEqual(RobotConfig.parseRemoteURL("robot.example.org")?.absoluteString, "https://robot.example.org")
    }

    func testRemoteURLDropsPathAndWhitespace() {
        XCTAssertEqual(RobotConfig.parseRemoteURL("  https://robot.example.org/api/v2/ \n")?.absoluteString, "https://robot.example.org")
    }

    func testRemoteURLRejectsEmptyAndOtherSchemes() {
        XCTAssertNil(RobotConfig.parseRemoteURL(nil))
        XCTAssertNil(RobotConfig.parseRemoteURL("   "))
        XCTAssertNil(RobotConfig.parseRemoteURL("ftp://robot.example.org"))
        XCTAssertNil(RobotConfig.parseRemoteURL("https://"))
    }

    func testEmptyRemoteURLIsStoredAsNil() {
        let config = RobotConfig(name: "R", host: "192.168.1.10", remoteURL: "  ")
        XCTAssertNil(config.remoteURL)
        XCTAssertFalse(config.hasRemoteAddress)
    }

    func testRemoteURLSurvivesEncoding() throws {
        let config = RobotConfig(name: "R", host: "192.168.1.10", remoteURL: "https://robot.example.org")
        let decoded = try JSONDecoder().decode(RobotConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.remoteURL, "https://robot.example.org")
        XCTAssertTrue(decoded.hasRemoteAddress)
    }

    func testStoredConfigWithoutRemoteURLStillDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"R","host":"192.168.1.10","useSSL":false,"ignoreCertificateErrors":false}"#
        let decoded = try JSONDecoder().decode(RobotConfig.self, from: Data(json.utf8))
        XCTAssertNil(decoded.remoteURL)
        XCTAssertEqual(decoded.host, "192.168.1.10")
    }

    // MARK: - Encryption warning

    func testRemoteHTTPSIsEncryptedEvenIfHomeIsHTTP() {
        let config = RobotConfig(name: "R", host: "192.168.1.10", useSSL: false, remoteURL: "https://robot.example.org")
        XCTAssertTrue(config.isEncrypted(via: .remote))
        XCTAssertFalse(config.isEncrypted(via: .home))
        XCTAssertFalse(config.isEncrypted(via: nil))
    }

    func testRemoteHTTPIsNotEncrypted() {
        let config = RobotConfig(name: "R", host: "192.168.1.10", useSSL: true, remoteURL: "http://robot.example.org")
        XCTAssertFalse(config.isEncrypted(via: .remote))
        XCTAssertTrue(config.isEncrypted(via: .home))
    }

    func testWithoutRemoteFollowsHomeSetting() {
        let config = RobotConfig(name: "R", host: "192.168.1.10", useSSL: true)
        XCTAssertTrue(config.isEncrypted(via: .remote))
    }

    // MARK: - Login

    func testConnectionTestUsesEnteredPasswordWithoutKeychain() {
        let config = RobotConfig(name: "R", host: "192.168.1.10", username: "user", password: "secret")
        XCTAssertEqual(ValetudoAPI.basicAuthorization(for: config, keychainPassword: nil), "Basic dXNlcjpzZWNyZXQ=")
    }

    func testSavedRobotUsesKeychainPassword() {
        let config = RobotConfig(name: "R", host: "192.168.1.10", username: "user")
        XCTAssertEqual(ValetudoAPI.basicAuthorization(for: config, keychainPassword: "secret"), "Basic dXNlcjpzZWNyZXQ=")
    }

    func testNoLoginWithoutUsername() {
        let config = RobotConfig(name: "R", host: "192.168.1.10", password: "secret")
        XCTAssertNil(ValetudoAPI.basicAuthorization(for: config, keychainPassword: "secret"))
    }

    // MARK: - API without remote address

    func testAPIWithoutRemoteStaysHome() async {
        let api = ValetudoAPI(config: RobotConfig(name: "R", host: "192.168.1.10"))
        let endpoint = await api.activeEndpoint()
        let hasRemote = await api.hasRemoteAddress
        XCTAssertEqual(endpoint, .home)
        XCTAssertFalse(hasRemote)
    }
}
