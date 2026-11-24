import Foundation
import os

enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let error): return error.localizedDescription
        case .invalidResponse: return "Invalid response"
        case .httpError(let code): return "HTTP Error: \(code)"
        case .decodingError(let error): return "Decoding error: \(error.localizedDescription)"
        }
    }
}

actor ValetudoAPI {
    private let config: RobotConfig
    private let session: URLSession
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.valetudio", category: "API")
    private let decoder: JSONDecoder
    private let sessionDelegate: SSLSessionDelegate?
    private let homeBaseURL: URL?
    private let remoteBaseURL: URL?
    private var endpoints: EndpointSelector
    private var resolveTask: Task<Void, Never>?
    // Short timeout: probing the home address away from home must not hold up the request.
    private let probeSession: URLSession
    // Separate SSE sessions for state and map, so one hanging stream does not block the other.
    private var _sseStateSession: URLSession?
    private var _sseMapSession: URLSession?

    private func makeSSESession() -> URLSession {
        let sseConfig = URLSessionConfiguration.default
        sseConfig.timeoutIntervalForRequest = .infinity
        sseConfig.timeoutIntervalForResource = .infinity
        // One connection per host, parallel auth connections end in 401.
        sseConfig.httpMaximumConnectionsPerHost = 1
        if let delegate = sessionDelegate {
            return URLSession(configuration: sseConfig, delegate: delegate, delegateQueue: nil)
        }
        return URLSession(configuration: sseConfig)
    }

    private var sseStateSession: URLSession {
        if let existing = _sseStateSession { return existing }
        let s = makeSSESession()
        _sseStateSession = s
        return s
    }

    private var sseMapSession: URLSession {
        if let existing = _sseMapSession { return existing }
        let s = makeSSESession()
        _sseMapSession = s
        return s
    }

    deinit {
        // Long-lived SSE sessions leak without invalidation and exhaust the server's auth connections (401).
        _sseStateSession?.invalidateAndCancel()
        _sseMapSession?.invalidateAndCancel()
    }

    init(config: RobotConfig) {
        self.config = config

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30

        self.homeBaseURL = config.baseURL
        self.remoteBaseURL = config.remoteBaseURL
        self.endpoints = EndpointSelector(hasRemote: config.remoteBaseURL != nil)

        let probeConfiguration = URLSessionConfiguration.default
        probeConfiguration.timeoutIntervalForRequest = 2
        probeConfiguration.timeoutIntervalForResource = 3

        if config.useSSL && config.ignoreCertificateErrors {
            let delegate = SSLSessionDelegate(trustedHost: config.baseURL?.host)
            self.sessionDelegate = delegate
            self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            self.probeSession = URLSession(configuration: probeConfiguration, delegate: delegate, delegateQueue: nil)
        } else {
            self.sessionDelegate = nil
            self.session = URLSession(configuration: configuration)
            self.probeSession = URLSession(configuration: probeConfiguration)
        }

        self.decoder = JSONDecoder()
    }
}

// MARK: - SSL Session Delegate for Self-Signed Certificates
private final class SSLSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    // Only the home address may have a self-signed certificate; the address away from home is checked normally.
    private let trustedHost: String?

    init(trustedHost: String?) {
        self.trustedHost = trustedHost
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == trustedHost,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

extension ValetudoAPI {

    // MARK: - Address Selection

    /// Address the last request went to.
    func activeEndpoint() -> EndpointSelector.Endpoint {
        endpoints.active
    }

    var hasRemoteAddress: Bool {
        endpoints.hasRemote
    }

    /// Chooses the address again if the network changed since the last choice.
    func refreshEndpoint() async -> EndpointSelector.Endpoint {
        await currentEndpoint()
    }

    private func baseURL(for endpoint: EndpointSelector.Endpoint) -> URL? {
        endpoint == .remote ? remoteBaseURL : homeBaseURL
    }

    private func currentEndpoint() async -> EndpointSelector.Endpoint {
        let generation = NetworkPathWatcher.shared.generation
        if endpoints.needsResolve(now: Date(), pathGeneration: generation) {
            if let running = resolveTask {
                await running.value
            } else {
                let task = Task { await self.resolveEndpoint(pathGeneration: generation) }
                resolveTask = task
                await task.value
                resolveTask = nil
            }
        }
        return endpoints.active
    }

    private func resolveEndpoint(pathGeneration: Int) async {
        let homeReachable = await isReachable(homeBaseURL, session: probeSession)
        let previous = endpoints.active
        endpoints.resolve(homeReachable: homeReachable, now: Date(), pathGeneration: pathGeneration)
        if endpoints.active != previous {
            logger.info("Address switched to \(self.endpoints.active.rawValue, privacy: .public)")
        }
    }

    /// Any HTTP answer counts: a 401 still means the robot is there.
    private func isReachable(_ base: URL?, session: URLSession) async -> Bool {
        guard let base, let request = try? makeRequest("/robot", base: base) else { return false }
        do {
            let (_, response) = try await session.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }

    private func makeRequest(_ path: String, base: URL, method: String = "GET") throws -> URLRequest {
        guard let url = URL(string: "/api/v2\(path)", relativeTo: base) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let authorization = Self.basicAuthorization(for: config, keychainPassword: KeychainStore.password(for: config.id)) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// An unsaved robot (connection test) still carries its password; saved ones keep it in the Keychain.
    static func basicAuthorization(for config: RobotConfig, keychainPassword: String?) -> String? {
        guard let username = config.username, !username.isEmpty,
              let password = config.password ?? keychainPassword,
              let data = "\(username):\(password)".data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    /// Sends on the active address; if it cannot be reached, once more on the other one.
    private func send<T>(
        _ path: String,
        method: String = "GET",
        prepare: (inout URLRequest) -> Void = { _ in },
        _ perform: (URLRequest) async throws -> T
    ) async throws -> T {
        let endpoint = await currentEndpoint()
        guard let base = baseURL(for: endpoint) else { throw APIError.invalidURL }
        var request = try makeRequest(path, base: base, method: method)
        prepare(&request)
        do {
            return try await perform(request)
        } catch where EndpointSelector.isUnreachable(error) {
            guard let next = endpoints.failover(from: endpoint, now: Date(), pathGeneration: NetworkPathWatcher.shared.generation),
                  next != endpoint,
                  let otherBase = baseURL(for: next) else { throw error }
            logger.info("Address \(endpoint.rawValue, privacy: .public) unreachable, retrying on \(next.rawValue, privacy: .public)")
            var retry = try makeRequest(path, base: otherBase, method: method)
            prepare(&retry)
            return try await perform(retry)
        }
    }

    /// Tests each configured address on its own, for the connection test in the settings.
    func checkAddresses() async -> (home: Bool, remote: Bool?) {
        async let home = isReachableWithLogin(homeBaseURL)
        async let remote: Bool? = remoteBaseURL == nil ? nil : isReachableWithLogin(remoteBaseURL)
        return await (home, remote)
    }

    private func isReachableWithLogin(_ base: URL?) async -> Bool {
        guard let base, let request = try? makeRequest("/robot", base: base) else { return false }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return false }
            _ = try decoder.decode(RobotInfo.self, from: data)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Base Request
    private func request<T: Decodable>(_ endpoint: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let data = try await send(endpoint, method: method, prepare: { request in
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }) { request in
            let (data, response) = try await self.session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.httpError(httpResponse.statusCode)
            }
            return data
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func requestVoid(_ endpoint: String, method: String = "PUT", body: Data? = nil) async throws {
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            logger.info("Request: \(method, privacy: .public) \(endpoint, privacy: .public) body: \(bodyString, privacy: .public)")
        } else {
            logger.info("Request: \(method, privacy: .public) \(endpoint, privacy: .public)")
        }

        try await send(endpoint, method: method, prepare: { request in
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }) { request in
            let (data, response) = try await self.session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            self.logger.info("Response: \(httpResponse.statusCode, privacy: .public) for \(method, privacy: .public) \(endpoint, privacy: .public)")
            guard (200...299).contains(httpResponse.statusCode) else {
                if let responseBody = String(data: data, encoding: .utf8), !responseBody.isEmpty {
                    self.logger.error("Response body (\(httpResponse.statusCode, privacy: .public)): \(responseBody, privacy: .public)")
                }
                throw APIError.httpError(httpResponse.statusCode)
            }
        }
    }

    // MARK: - Robot Info
    func getRobotInfo() async throws -> RobotInfo {
        try await request("/robot")
    }

    func getCapabilities() async throws -> Capabilities {
        try await request("/robot/capabilities")
    }

    func getRobotProperties() async throws -> RobotProperties {
        try await request("/robot/properties")
    }

    // MARK: - State
    func getAttributes() async throws -> [RobotAttribute] {
        try await request("/robot/state/attributes")
    }

    func getMap() async throws -> RobotMap {
        try await request("/robot/state/map")
    }

    // MARK: - Segments
    func getSegments() async throws -> [Segment] {
        try await request("/robot/capabilities/MapSegmentationCapability")
    }

    // MARK: - Controls
    func basicControl(action: BasicAction) async throws {
        let body = try JSONEncoder().encode(BasicControlRequest(action: action.rawValue))
        try await requestVoid("/robot/capabilities/BasicControlCapability", body: body)
    }

    func cleanSegments(ids: [String], iterations: Int = 1, customOrder: Bool = false) async throws {
        let body = try JSONEncoder().encode(SegmentCleanRequest(segmentIds: ids, iterations: iterations, customOrder: customOrder ? true : nil))
        try await requestVoid("/robot/capabilities/MapSegmentationCapability", body: body)
    }

    func goTo(x: Int, y: Int) async throws {
        let body = try JSONEncoder().encode(GoToRequest(x: x, y: y))
        try await requestVoid("/robot/capabilities/GoToLocationCapability", body: body)
    }

    func locate() async throws {
        let body = try JSONEncoder().encode(["action": "locate"])
        try await requestVoid("/robot/capabilities/LocateCapability", body: body)
    }

    // MARK: - Consumables
    func getConsumables() async throws -> [Consumable] {
        try await request("/robot/capabilities/ConsumableMonitoringCapability")
    }

    func resetConsumable(type: String, subType: String?) async throws {
        var endpoint = "/robot/capabilities/ConsumableMonitoringCapability/\(type)"
        if let subType = subType {
            endpoint += "/\(subType)"
        }
        let body = try JSONEncoder().encode(ActionRequest(action: "reset"))
        try await requestVoid(endpoint, body: body)
    }

    // MARK: - Timers
    func getTimers() async throws -> [ValetudoTimer] {
        let response: [String: ValetudoTimer] = try await request("/timers")
        return Array(response.values)
    }

    func createTimer(_ timer: CreateTimerRequest) async throws {
        let body = try JSONEncoder().encode(timer)
        try await requestVoid("/timers", method: "POST", body: body)
    }

    func updateTimer(_ timer: ValetudoTimer) async throws {
        let body = try JSONEncoder().encode(timer)
        try await requestVoid("/timers/\(timer.id)", method: "PUT", body: body)
    }

    func deleteTimer(id: String) async throws {
        try await requestVoid("/timers/\(id)", method: "DELETE")
    }

    // MARK: - Segment Rename
    func renameSegment(id: String, name: String) async throws {
        let body = try JSONEncoder().encode(SegmentRenameRequest(segmentId: id, name: name))
        try await requestVoid("/robot/capabilities/MapSegmentRenameCapability", body: body)
    }

    // MARK: - Fan Speed Control
    func getFanSpeedPresets() async throws -> [String] {
        try await request("/robot/capabilities/FanSpeedControlCapability/presets")
    }

    func setFanSpeed(preset: String) async throws {
        let body = try JSONEncoder().encode(PresetControlRequest(name: preset))
        try await requestVoid("/robot/capabilities/FanSpeedControlCapability/preset", body: body)
    }

    // MARK: - Water Usage Control
    func getWaterUsagePresets() async throws -> [String] {
        try await request("/robot/capabilities/WaterUsageControlCapability/presets")
    }

    func setWaterUsage(preset: String) async throws {
        let body = try JSONEncoder().encode(PresetControlRequest(name: preset))
        try await requestVoid("/robot/capabilities/WaterUsageControlCapability/preset", body: body)
    }

    // MARK: - Statistics
    func getTotalStatistics() async throws -> [StatisticEntry] {
        try await request("/robot/capabilities/TotalStatisticsCapability")
    }

    func getCurrentStatistics() async throws -> [StatisticEntry] {
        try await request("/robot/capabilities/CurrentStatisticsCapability")
    }

    // MARK: - Do Not Disturb
    func getDoNotDisturb() async throws -> DoNotDisturbConfig {
        try await request("/robot/capabilities/DoNotDisturbCapability")
    }

    func setDoNotDisturb(config: DoNotDisturbConfig) async throws {
        let body = try JSONEncoder().encode(config)
        try await requestVoid("/robot/capabilities/DoNotDisturbCapability", body: body)
    }

    // MARK: - Speaker Volume
    func getSpeakerVolume() async throws -> Int {
        let response: SpeakerVolumeResponse = try await request("/robot/capabilities/SpeakerVolumeControlCapability")
        return response.volume
    }

    func setSpeakerVolume(_ volume: Int) async throws {
        let body = try JSONEncoder().encode(SpeakerVolumeRequest(volume: volume))
        try await requestVoid("/robot/capabilities/SpeakerVolumeControlCapability", body: body)
    }

    // MARK: - Speaker Test
    func testSpeaker() async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: "play_test_sound"))
        try await requestVoid("/robot/capabilities/SpeakerTestCapability", body: body)
    }

    // MARK: - Carpet Mode
    func getCarpetMode() async throws -> Bool {
        let response: EnabledResponse = try await request("/robot/capabilities/CarpetModeControlCapability")
        return response.enabled
    }

    func setCarpetMode(enabled: Bool) async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: enabled ? "enable" : "disable"))
        try await requestVoid("/robot/capabilities/CarpetModeControlCapability", body: body)
    }

    // MARK: - Persistent Map
    func getPersistentMap() async throws -> Bool {
        let response: EnabledResponse = try await request("/robot/capabilities/PersistentMapControlCapability")
        return response.enabled
    }

    func setPersistentMap(enabled: Bool) async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: enabled ? "enable" : "disable"))
        try await requestVoid("/robot/capabilities/PersistentMapControlCapability", body: body)
    }

    // MARK: - Mapping Pass
    func startMappingPass() async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: "start_mapping"))
        try await requestVoid("/robot/capabilities/MappingPassCapability", body: body)
    }

    // MARK: - Map Reset
    func resetMap() async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: "reset"))
        try await requestVoid("/robot/capabilities/MapResetCapability", body: body)
    }

    // MARK: - Zone Cleaning
    func cleanZones(_ zones: [CleaningZone]) async throws {
        let body = try JSONEncoder().encode(ZoneCleanRequest(zones: zones))
        try await requestVoid("/robot/capabilities/ZoneCleaningCapability", body: body)
    }

    // MARK: - Virtual Restrictions
    func getVirtualRestrictions() async throws -> VirtualRestrictions {
        try await request("/robot/capabilities/CombinedVirtualRestrictionsCapability")
    }

    func setVirtualRestrictions(_ restrictions: VirtualRestrictions) async throws {
        let body = try JSONEncoder().encode(VirtualRestrictionsRequest(restrictions: restrictions))
        try await requestVoid("/robot/capabilities/CombinedVirtualRestrictionsCapability", body: body)
    }

    // MARK: - Map Annotations
    func getMapAnnotationsProperties() async throws -> MapAnnotationsProperties {
        try await request("/robot/capabilities/MapAnnotationsCapability/properties")
    }

    /// Replaces all map annotations; the PUT is replace-all, so pass the complete set.
    func setMapAnnotations(_ annotations: [MapAnnotation]) async throws {
        let body = try JSONEncoder().encode(annotations.map { MapAnnotationRequest($0) })
        try await requestVoid("/robot/capabilities/MapAnnotationsCapability", body: body)
    }

    // MARK: - Map Segment Edit
    func joinSegments(segmentAId: String, segmentBId: String) async throws {
        let body = try JSONEncoder().encode(JoinSegmentsRequest(segmentAId: segmentAId, segmentBId: segmentBId))
        try await requestVoid("/robot/capabilities/MapSegmentEditCapability", body: body)
    }

    func splitSegment(segmentId: String, pointA: ZonePoint, pointB: ZonePoint) async throws {
        let body = try JSONEncoder().encode(SplitSegmentRequest(segmentId: segmentId, pointA: pointA, pointB: pointB))
        try await requestVoid("/robot/capabilities/MapSegmentEditCapability", body: body)
    }

    // MARK: - Operation Mode Control
    func getOperationModePresets() async throws -> [String] {
        try await request("/robot/capabilities/OperationModeControlCapability/presets")
    }

    func setOperationMode(preset: String) async throws {
        let body = try JSONEncoder().encode(PresetControlRequest(name: preset))
        try await requestVoid("/robot/capabilities/OperationModeControlCapability/preset", body: body)
    }

    // MARK: - Auto Empty Dock
    // These dock capabilities read choices from `/properties` and use their own value keys, no `/presets`.

    func getAutoEmptyDockIntervalPresets() async throws -> [String] {
        let props: AutoEmptyIntervalProperties = try await request("/robot/capabilities/AutoEmptyDockAutoEmptyIntervalControlCapability/properties")
        return props.supportedIntervals
    }

    func getAutoEmptyDockInterval() async throws -> String {
        let response: AutoEmptyIntervalResponse = try await request("/robot/capabilities/AutoEmptyDockAutoEmptyIntervalControlCapability")
        return response.interval
    }

    func setAutoEmptyDockInterval(preset: String) async throws {
        let body = try JSONEncoder().encode(["interval": preset])
        try await requestVoid("/robot/capabilities/AutoEmptyDockAutoEmptyIntervalControlCapability", body: body)
    }

    func getAutoEmptyDockDurationPresets() async throws -> [String] {
        let props: AutoEmptyDurationProperties = try await request("/robot/capabilities/AutoEmptyDockAutoEmptyDurationControlCapability/properties")
        return props.supportedDurations
    }

    func getAutoEmptyDockDuration() async throws -> String {
        let response: DurationResponse = try await request("/robot/capabilities/AutoEmptyDockAutoEmptyDurationControlCapability")
        return response.duration
    }

    func setAutoEmptyDockDuration(preset: String) async throws {
        let body = try JSONEncoder().encode(["duration": preset])
        try await requestVoid("/robot/capabilities/AutoEmptyDockAutoEmptyDurationControlCapability", body: body)
    }

    func triggerAutoEmptyDock() async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: "trigger"))
        try await requestVoid("/robot/capabilities/AutoEmptyDockManualTriggerCapability", body: body)
    }

    // MARK: - Mop Dock
    func triggerMopDockClean() async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: "trigger"))
        try await requestVoid("/robot/capabilities/MopDockCleanManualTriggerCapability", body: body)
    }

    func triggerMopDockDry() async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: "trigger"))
        try await requestVoid("/robot/capabilities/MopDockDryManualTriggerCapability", body: body)
    }

    // MARK: - Manual Control
    func enableManualControl() async throws {
        let body = try JSONEncoder().encode(ManualControlRequest(action: "enable", movementCommand: nil))
        try await requestVoid("/robot/capabilities/ManualControlCapability", body: body)
    }

    func disableManualControl() async throws {
        let body = try JSONEncoder().encode(ManualControlRequest(action: "disable", movementCommand: nil))
        try await requestVoid("/robot/capabilities/ManualControlCapability", body: body)
    }

    func manualControl(movementCommand: String) async throws {
        let body = try JSONEncoder().encode(ManualControlRequest(action: "move", movementCommand: movementCommand))
        try await requestVoid("/robot/capabilities/ManualControlCapability", body: body)
    }

    // MARK: - High Resolution Manual Control (for S5 Max etc.)
    func enableHighResManualControl() async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: "enable"))
        try await requestVoid("/robot/capabilities/HighResolutionManualControlCapability", body: body)
    }

    func disableHighResManualControl() async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: "disable"))
        try await requestVoid("/robot/capabilities/HighResolutionManualControlCapability", body: body)
    }

    func highResManualControl(velocity: Double, angle: Double) async throws {
        let body = try JSONEncoder().encode(HighResManualControlRequest(action: "move", vector: HighResManualControlVector(velocity: velocity, angle: angle)))
        try await requestVoid("/robot/capabilities/HighResolutionManualControlCapability", body: body)
    }

    // MARK: - Quirks
    func getQuirks() async throws -> [Quirk] {
        try await request("/robot/capabilities/QuirksCapability")
    }

    func setQuirk(id: String, value: String) async throws {
        let body = try JSONEncoder().encode(QuirkSetRequest(id: id, value: value))
        try await requestVoid("/robot/capabilities/QuirksCapability", body: body)
    }

    // MARK: - WiFi
    func getWifiStatus() async throws -> WifiStatus {
        try await request("/robot/capabilities/WifiConfigurationCapability")
    }

    func scanWifi() async throws -> [WifiNetwork] {
        try await request("/robot/capabilities/WifiScanCapability")
    }

    func setWifiConfig(ssid: String, password: String) async throws {
        let body = try JSONEncoder().encode(WifiConfigRequest(ssid: ssid, password: password))
        try await requestVoid("/robot/capabilities/WifiConfigurationCapability", body: body)
    }

    // MARK: - Key Lock
    func getKeyLock() async throws -> Bool {
        let response: EnabledResponse = try await request("/robot/capabilities/KeyLockCapability")
        return response.enabled
    }

    func setKeyLock(enabled: Bool) async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: enabled ? "enable" : "disable"))
        try await requestVoid("/robot/capabilities/KeyLockCapability", body: body)
    }

    // MARK: - Obstacle Avoidance
    func getObstacleAvoidance() async throws -> Bool {
        let response: EnabledResponse = try await request("/robot/capabilities/ObstacleAvoidanceControlCapability")
        return response.enabled
    }

    func setObstacleAvoidance(enabled: Bool) async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: enabled ? "enable" : "disable"))
        try await requestVoid("/robot/capabilities/ObstacleAvoidanceControlCapability", body: body)
    }

    // MARK: - Pet Obstacle Avoidance
    func getPetObstacleAvoidance() async throws -> Bool {
        let response: EnabledResponse = try await request("/robot/capabilities/PetObstacleAvoidanceControlCapability")
        return response.enabled
    }

    func setPetObstacleAvoidance(enabled: Bool) async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: enabled ? "enable" : "disable"))
        try await requestVoid("/robot/capabilities/PetObstacleAvoidanceControlCapability", body: body)
    }

    // MARK: - Carpet Sensor Mode
    func getCarpetSensorMode() async throws -> String {
        let response: ModeResponse = try await request("/robot/capabilities/CarpetSensorModeControlCapability")
        return response.mode
    }

    func getCarpetSensorModePresets() async throws -> [String] {
        try await request("/robot/capabilities/CarpetSensorModeControlCapability/presets")
    }

    func setCarpetSensorMode(mode: String) async throws {
        let body = try JSONEncoder().encode(ModeRequest(mode: mode))
        try await requestVoid("/robot/capabilities/CarpetSensorModeControlCapability", body: body)
    }

    // MARK: - Collision Avoidant Navigation
    func getCollisionAvoidantNavigation() async throws -> Bool {
        let response: EnabledResponse = try await request("/robot/capabilities/CollisionAvoidantNavigationControlCapability")
        return response.enabled
    }

    func setCollisionAvoidantNavigation(enabled: Bool) async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: enabled ? "enable" : "disable"))
        try await requestVoid("/robot/capabilities/CollisionAvoidantNavigationControlCapability", body: body)
    }

    // MARK: - Mop Dock Auto Drying
    func getMopDockAutoDrying() async throws -> Bool {
        let response: EnabledResponse = try await request("/robot/capabilities/MopDockMopAutoDryingControlCapability")
        return response.enabled
    }

    func setMopDockAutoDrying(enabled: Bool) async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: enabled ? "enable" : "disable"))
        try await requestVoid("/robot/capabilities/MopDockMopAutoDryingControlCapability", body: body)
    }

    // MARK: - Mop Dock Wash Temperature
    func getMopDockWashTemperaturePresets() async throws -> [String] {
        let props: WashTemperatureProperties = try await request("/robot/capabilities/MopDockMopWashTemperatureControlCapability/properties")
        return props.supportedTemperatures
    }

    func getMopDockWashTemperature() async throws -> String {
        let response: TemperatureResponse = try await request("/robot/capabilities/MopDockMopWashTemperatureControlCapability")
        return response.temperature
    }

    func setMopDockWashTemperature(preset: String) async throws {
        let body = try JSONEncoder().encode(["temperature": preset])
        try await requestVoid("/robot/capabilities/MopDockMopWashTemperatureControlCapability", body: body)
    }

    func getMopDockDryingTimePresets() async throws -> [String] {
        let props: DryingTimeProperties = try await request("/robot/capabilities/MopDockMopDryingTimeControlCapability/properties")
        return props.supportedDurations
    }

    func getMopDockDryingTime() async throws -> String {
        let response: DurationResponse = try await request("/robot/capabilities/MopDockMopDryingTimeControlCapability")
        return response.duration
    }

    func setMopDockDryingTime(preset: String) async throws {
        let body = try JSONEncoder().encode(["duration": preset])
        try await requestVoid("/robot/capabilities/MopDockMopDryingTimeControlCapability", body: body)
    }

    // MARK: - Map Segment Material Control
    func getSegmentMaterialProperties() async throws -> SegmentMaterialProperties {
        try await request("/robot/capabilities/MapSegmentMaterialControlCapability/properties")
    }

    func setSegmentMaterial(segmentId: String, material: String) async throws {
        let body = try JSONEncoder().encode(SegmentMaterialRequest(action: "set_material", segmentId: segmentId, material: material))
        try await requestVoid("/robot/capabilities/MapSegmentMaterialControlCapability", body: body)
    }

    // MARK: - Floor Material Direction Aware Navigation
    func getFloorMaterialNavigation() async throws -> Bool {
        let response: EnabledResponse = try await request("/robot/capabilities/FloorMaterialDirectionAwareNavigationControlCapability")
        return response.enabled
    }

    func setFloorMaterialNavigation(enabled: Bool) async throws {
        let body = try JSONEncoder().encode(ActionRequest(action: enabled ? "enable" : "disable"))
        try await requestVoid("/robot/capabilities/FloorMaterialDirectionAwareNavigationControlCapability", body: body)
    }

    // MARK: - MQTT
    func getMQTTConfig() async throws -> MQTTConfig {
        try await request("/valetudo/config/interfaces/mqtt")
    }

    func setMQTTConfig(_ config: MQTTConfig) async throws {
        let body = try JSONEncoder().encode(config)
        try await requestVoid("/valetudo/config/interfaces/mqtt", body: body)
    }

    // MARK: - NTP
    func getNTPConfig() async throws -> NTPConfig {
        try await request("/ntpclient/config")
    }

    func setNTPConfig(_ config: NTPConfig) async throws {
        let body = try JSONEncoder().encode(config)
        try await requestVoid("/ntpclient/config", body: body)
    }

    func getNTPStatus() async throws -> NTPStatus {
        try await request("/ntpclient/status")
    }

    // MARK: - System Info
    func getValetudoVersion() async throws -> ValetudoVersion {
        try await request("/valetudo/version")
    }

    func getSystemHostInfo() async throws -> SystemHostInfo {
        try await request("/system/host/info")
    }

    func getUpdaterState() async throws -> UpdaterState {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1" {
            return UpdaterState(
                __class: "ValetudoUpdaterApprovalPendingState",
                busy: false,
                currentVersion: "2025.12.0",
                version: "2026.04.0",
                releaseTimestamp: "2026-04-10T00:00:00Z",
                downloadUrl: "https://github.com/Hypfer/Valetudo/releases/download/2026.04.0/valetudo.upx",
                downloadPath: nil,
                metaData: nil
            )
        }
        #endif
        return try await request("/updater/state")
    }

    func checkForUpdates() async throws {
        let body = try JSONEncoder().encode(["action": "check"])
        try await requestVoid("/updater", body: body)
    }

    func downloadUpdate() async throws {
        let body = try JSONEncoder().encode(["action": "download"])
        try await requestVoid("/updater", body: body)
    }

    func applyUpdate() async throws {
        let body = try JSONEncoder().encode(["action": "apply"])
        try await requestVoid("/updater", body: body)
    }

    // MARK: - SSE Streaming
    func streamStateLines() async throws -> URLSession.AsyncBytes {
        try await send("/robot/state/attributes/sse") { request in
            let (bytes, response) = try await self.sseStateSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw APIError.httpError(httpResponse.statusCode)
            }
            return bytes
        }
    }

    func streamMapLines() async throws -> URLSession.AsyncBytes {
        try await send("/robot/state/map/sse") { request in
            let (bytes, response) = try await self.sseMapSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw APIError.httpError(httpResponse.statusCode)
            }
            return bytes
        }
    }

    // MARK: - Map Snapshots
    func getMapSnapshots() async throws -> [MapSnapshot] {
        try await request("/robot/capabilities/MapSnapshotCapability")
    }

    func restoreMapSnapshot(id: String) async throws {
        let body = try JSONEncoder().encode(["action": "restore", "id": id])
        try await requestVoid("/robot/capabilities/MapSnapshotCapability", body: body)
    }

    // MARK: - Pending Map Change
    func getPendingMapChange() async throws -> PendingMapChangeState {
        try await request("/robot/capabilities/PendingMapChangeHandlingCapability")
    }

    func handlePendingMapChange(action: String) async throws {
        let body = try JSONEncoder().encode(["action": action])
        try await requestVoid("/robot/capabilities/PendingMapChangeHandlingCapability", body: body)
    }

    // MARK: - Clean Route Control
    func getCleanRoute() async throws -> CleanRouteState {
        try await request("/robot/capabilities/CleanRouteControlCapability")
    }

    func setCleanRoute(route: String) async throws {
        let body = try JSONEncoder().encode(["route": route])
        try await requestVoid("/robot/capabilities/CleanRouteControlCapability", body: body)
    }

    func getCleanRoutePresets() async throws -> [String] {
        try await request("/robot/capabilities/CleanRouteControlCapability/presets")
    }

    // MARK: - Valetudo Events
    func dismissEvent(id: String) async throws {
        let body = try JSONEncoder().encode(["action": "dismiss"])
        try await requestVoid("/valetudo/events/\(id)", body: body)
    }

    func getEvents() async throws -> [ValetudoEvent] {
        // Events API may return dictionary {id: event} or array — try dict first
        do {
            let dict: [String: ValetudoEvent] = try await request("/valetudo/events")
            return Array(dict.values).sorted { $0.timestamp > $1.timestamp }
        } catch {
            // Fallback: try as array
            return try await request("/valetudo/events")
        }
    }

    // MARK: - Obstacle Images
    func getObstacleImage(id: String) async throws -> Data {
        try await send("/robot/capabilities/ObstacleImagesCapability/img/\(id)") { request in
            let (data, response) = try await self.session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.httpError(httpResponse.statusCode)
            }
            return data
        }
    }

    // MARK: - Voice Pack
    func getVoicePackState() async throws -> VoicePackState {
        try await request("/robot/capabilities/VoicePackManagementCapability")
    }

    func setVoicePack(id: String) async throws {
        let body = try JSONEncoder().encode(["action": "download", "id": id])
        try await requestVoid("/robot/capabilities/VoicePackManagementCapability", body: body)
    }

    // MARK: - Connection Check
    func checkConnection() async -> Bool {
        do {
            let _: RobotInfo = try await request("/robot")
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Robot Properties Models
// MARK: - Dock Capability Models
// These capabilities use their own field name instead of the preset `name`.

struct AutoEmptyIntervalProperties: Codable {
    let supportedIntervals: [String]
}

struct AutoEmptyIntervalResponse: Codable {
    let interval: String
}

struct AutoEmptyDurationProperties: Codable {
    let supportedDurations: [String]
}

struct DryingTimeProperties: Codable {
    let supportedDurations: [String]
}

struct DurationResponse: Codable {
    let duration: String
}

struct WashTemperatureProperties: Codable {
    let supportedTemperatures: [String]
}

struct TemperatureResponse: Codable {
    let temperature: String
}

struct RobotProperties: Codable {
    let firmwareVersion: String?
    let model: String?
    let manufacturer: String?
    let metaData: RobotPropertiesMetaData?

    enum CodingKeys: String, CodingKey {
        case firmwareVersion
        case model
        case manufacturer
        case metaData
    }
}

struct RobotPropertiesMetaData: Codable {
    let manufacturerSerialNumber: String?
}

// MARK: - Voice Pack Models
struct VoicePack: Codable, Identifiable {
    let id: String
    let name: String
    let installed: Bool
}

struct VoicePackState: Codable {
    let currentLanguage: VoicePack?
    let supportedLanguages: [VoicePack]?

    enum CodingKeys: String, CodingKey {
        case currentLanguage = "current_language"
        case supportedLanguages = "supported_languages"
    }
}

// MARK: - ValetudoAPIProtocol Conformance
extension ValetudoAPI: ValetudoAPIProtocol {}
