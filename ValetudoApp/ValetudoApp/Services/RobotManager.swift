import Foundation
import SwiftUI
import os
import Observation

@MainActor
@Observable
class RobotManager {
    var robots: [RobotConfig] = []
    var robotStates: [UUID: RobotStatus] = [:]
    var robotUpdateAvailable: [UUID: Bool] = [:]
    var robotErrors: [UUID: RobotErrorInfo] = [:]

    // MARK: - Active Robot
    var activeRobotId: UUID? {
        didSet {
            if oldValue != activeRobotId {
                restartRefreshing()
            }
        }
    }

    // MARK: - Centralized Room Selection
    @ObservationIgnored var roomSelections: [UUID: [String]] = [:]
    @ObservationIgnored var iterationSelections: [UUID: Int] = [:]

    func toggleRoom(_ id: String, for robotId: UUID) {
        var current = roomSelections[robotId] ?? []
        if current.contains(id) {
            current.removeAll { $0 == id }
        } else {
            current.append(id)
        }
        roomSelections[robotId] = current
    }

    func clearRoomSelection(for robotId: UUID) {
        roomSelections[robotId] = nil
        iterationSelections[robotId] = nil
    }

    func selectedRooms(for robotId: UUID) -> [String] {
        roomSelections[robotId] ?? []
    }

    func selectedIterationCount(for robotId: UUID) -> Int {
        iterationSelections[robotId] ?? 1
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.valetudio", category: "RobotManager")
    @ObservationIgnored private var apis: [UUID: ValetudoAPI] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let stateTracker = RobotStateTracker()
    // Failed polls in a row; only past the threshold is a robot offline, so a single timeout does not flip it.
    @ObservationIgnored private var consecutiveFailures: [UUID: Int] = [:]
    private let offlineFailureThreshold = 3
    @ObservationIgnored private var lastConsumableCheck: [UUID: Date] = [:]
    private let storageKey = RobotConfigStore.legacyKey
    private let robotIdsKey = RobotConfigStore.idsKey
    private let notificationService = NotificationService.shared
    @ObservationIgnored private let sseManager = SSEConnectionManager()

    // MARK: - Capabilities Cache
    @ObservationIgnored private var capabilitiesCache: [UUID: [String]] = [:]
    @ObservationIgnored private var capabilitiesCacheDate: [UUID: Date] = [:]
    private let capabilitiesTTL: TimeInterval = 86400 // 24 Stunden

    init() {
        loadRobots()
        startRefreshing()
        notificationService.setupCategories()

        Task {
            await notificationService.requestAuthorization()
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Robot Management
    func addRobot(_ config: RobotConfig) {
        robots.append(config)
        if let pw = config.password, !pw.isEmpty {
            KeychainStore.save(password: pw, for: config.id)
        }
        apis[config.id] = ValetudoAPI(config: config)
        saveRobots()
        Task { await refreshRobot(config.id) }
    }

    func updateRobot(_ config: RobotConfig) {
        if let index = robots.firstIndex(where: { $0.id == config.id }) {
            robots[index] = config
            if let pw = config.password, !pw.isEmpty {
                KeychainStore.save(password: pw, for: config.id)
            }
            apis[config.id] = ValetudoAPI(config: config)
            saveRobots()
            Task { await refreshRobot(config.id) }
        }
    }

    func removeRobot(_ id: UUID) {
        // Disconnect SSE before clearing state so stream cleanup completes
        Task { await sseManager.disconnect(robotId: id) }
        KeychainStore.delete(for: id)
        KeychainStore.deleteRobotConfig(for: id)
        robots.removeAll { $0.id == id }
        apis.removeValue(forKey: id)
        robotStates.removeValue(forKey: id)
        robotErrors.removeValue(forKey: id)
        stateTracker.forget(id)
        saveRobots()
        MapCacheService.shared.deleteCache(for: id)
        SkippedUpdateStore(robotId: id).clear()
    }

    func getAPI(for id: UUID) -> ValetudoAPI? {
        apis[id]
    }

    func getRobotName(for id: UUID) -> String {
        robots.first { $0.id == id }?.name ?? "Robot"
    }

    // MARK: - Capabilities Cache

    func cachedCapabilities(for robotId: UUID) -> [String]? {
        guard let date = capabilitiesCacheDate[robotId],
              Date().timeIntervalSince(date) < capabilitiesTTL else { return nil }
        return capabilitiesCache[robotId]
    }

    func cacheCapabilities(_ capabilities: [String], for robotId: UUID) {
        capabilitiesCache[robotId] = capabilities
        capabilitiesCacheDate[robotId] = Date()
    }

    func invalidateCapabilities(for robotId: UUID) {
        capabilitiesCache.removeValue(forKey: robotId)
        capabilitiesCacheDate.removeValue(forKey: robotId)
    }

    // MARK: - Status Refresh

    private func restartRefreshing() {
        refreshTask?.cancel()
        startRefreshing()
    }

    private func startRefreshing() {
        refreshTask = Task {
            while !Task.isCancelled {
                // Live SSE stream for every robot, so the list stays current and inactive robots do not turn unreachable.
                for robot in robots {
                    guard let api = apis[robot.id] else { continue }
                    let sseActive = await sseManager.isSSEActive(for: robot.id)
                    let sseSuspended = await sseManager.isSuspended(for: robot.id)
                    if !sseActive && !sseSuspended {
                        let robotId = robot.id
                        await sseManager.connect(
                            robotId: robotId,
                            api: api,
                            isLocalNetwork: robot.isLocalNetwork,
                            // The SSE manager keeps these callbacks; a strong reference would form a cycle.
                            onAttributesUpdate: { [weak manager = self] attrs in
                                Task { @MainActor [weak manager] in
                                    manager?.applyAttributeUpdate(attrs, for: robotId)
                                }
                            },
                            onConnectionChange: { [weak manager = self] connected in
                                Task { @MainActor [weak manager] in
                                    manager?.sseConnectionChanged(connected, for: robotId)
                                }
                            }
                        )
                    }
                }

                // Poll only robots without active SSE; with activeRobotId set, only that one.
                let robotsToPoll = activeRobotId != nil
                    ? robots.filter { $0.id == activeRobotId }
                    : robots

                await withTaskGroup(of: Void.self) { group in
                    for robot in robotsToPoll {
                        group.addTask {
                            let sseActive = await self.sseManager.isSSEActive(for: robot.id)
                            let sseSuspended = await self.sseManager.isSuspended(for: robot.id)
                            if !sseActive && !sseSuspended {
                                await self.refreshRobot(robot.id)
                            }
                        }
                    }
                }

                // 15 s in the background, SSE carries the live updates.
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func refreshAllRobots() async {
        await withTaskGroup(of: Void.self) { group in
            for robot in robots {
                group.addTask { await self.refreshRobot(robot.id) }
            }
        }
    }

    func refreshRobot(_ id: UUID) async {
        guard let api = apis[id] else { return }
        let robotName = getRobotName(for: id)

        do {
            let attributes = try await api.getAttributes()
            let info = try await api.getRobotInfo()

            let newStatus = RobotStatus(
                isOnline: true,
                attributes: attributes,
                info: info
            )

            // Erfolgreicher Poll — Fehlerzähler zurücksetzen
            consecutiveFailures[id] = 0

            notifyStateEvents(stateTracker.apply(newStatus, for: id), robotId: id, robotName: robotName)
            updateDisplayedError(for: id)
            checkDockComponents(robotName: robotName, previous: robotStates[id], current: newStatus)

            if robotStates[id] != newStatus {
                robotStates[id] = newStatus
            }

            // Check for updates and consumables (in background, don't block refresh)
            Task {
                await self.checkUpdateForRobot(id)
                await self.checkConsumables(for: id)
            }
        } catch {
            // Below the threshold keep the previous status, so short timeouts do not flicker.
            let failures = (consecutiveFailures[id] ?? 0) + 1
            consecutiveFailures[id] = failures

            if failures < offlineFailureThreshold {
                logger.info("Robot \(id, privacy: .public) poll failed (\(failures)/\(self.offlineFailureThreshold)) — keeping previous status")
                return
            }

            // Schwellwert erreicht — jetzt als offline markieren
            let offlineStatus = RobotStatus(isOnline: false)
            _ = stateTracker.apply(offlineStatus, for: id)
            updateDisplayedError(for: id)
            if robotStates[id] != offlineStatus {
                robotStates[id] = offlineStatus
            }
        }
    }

    // MARK: - SSE Update Handling

    private func applyAttributeUpdate(_ attrs: [RobotAttribute], for id: UUID) {
        let existingInfo = robotStates[id]?.info
        let newStatus = RobotStatus(
            isOnline: true,
            attributes: attrs,
            info: existingInfo
        )
        let robotName = getRobotName(for: id)
        notifyStateEvents(stateTracker.apply(newStatus, for: id), robotId: id, robotName: robotName)
        updateDisplayedError(for: id)
        checkDockComponents(robotName: robotName, previous: robotStates[id], current: newStatus)
        if robotStates[id] != newStatus {
            robotStates[id] = newStatus
        }
    }

    private func sseConnectionChanged(_ connected: Bool, for id: UUID) {
        if connected {
            logger.info("SSE connection established for robot \(id, privacy: .public)")
        } else {
            logger.warning("SSE connection lost for robot \(id, privacy: .public) — falling back to polling")
        }
    }

    func checkUpdateForRobot(_ id: UUID) async {
        guard let api = apis[id] else { return }
        do {
            let updaterState = try await api.getUpdaterState()
            await MainActor.run {
                let newValue = updaterState.isUpdateAvailable
                    && !SkippedUpdateStore(robotId: id).isSkipped(updaterState.version)
                if self.robotUpdateAvailable[id] != newValue {
                    self.robotUpdateAvailable[id] = newValue
                }
            }
        } catch {
            logger.warning("checkUpdaterState: Not supported or failed for robot \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - State Change Notifications
    private func updateDisplayedError(for id: UUID) {
        let error = stateTracker.displayedError(for: id)
        if robotErrors[id] != error {
            robotErrors[id] = error
        }
    }

    private func notifyStateEvents(_ events: [RobotStateEvent], robotId: UUID, robotName: String) {
        for event in events {
            switch event {
            case .cleaningComplete(let area):
                notificationService.notifyCleaningComplete(robotName: robotName, area: area)
            case .stuck:
                notificationService.notifyRobotStuck(robotName: robotName)
            case .error(let error):
                notificationService.notifyRobotError(robotId: robotId, robotName: robotName, error: error)
            }
        }
    }

    private func checkDockComponents(robotName: String, previous: RobotStatus?, current: RobotStatus) {
        for component in current.newDockComponentProblems(since: previous) {
            notificationService.notifyDockComponent(robotName: robotName, component: component)
        }
    }

    // MARK: - Check Consumables
    func checkConsumables(for id: UUID) async {
        guard let api = apis[id] else { return }

        // Only check consumables once per hour to avoid spam
        if let lastCheck = lastConsumableCheck[id],
           Date().timeIntervalSince(lastCheck) < 3600 {
            return
        }

        lastConsumableCheck[id] = Date()
        let robotName = getRobotName(for: id)

        do {
            let consumables = try await api.getConsumables()
            for consumable in consumables {
                if consumable.remainingPercent < 15 {
                    notificationService.notifyConsumableLow(
                        robotName: robotName,
                        consumableName: consumable.displayName,
                        percent: Int(consumable.remainingPercent)
                    )
                }
            }
        } catch {
            // Silently ignore consumable check failures
        }
    }

    // MARK: - Persistence
    private func loadRobots() {
        var loadedRobots = RobotConfigStore.savedRobots()

        // Fallback: Migration von UserDefaults (bestehende Installs)
        let decoded = loadedRobots.isEmpty ? RobotConfigStore.legacyRobots() : []
        if !decoded.isEmpty {
            var migratedRobots = decoded
            for (index, robot) in decoded.enumerated() {
                // Passwort in Keychain migrieren (falls noch nicht geschehen)
                if KeychainStore.password(for: robot.id) == nil,
                   let legacyPassword = robot.password, !legacyPassword.isEmpty {
                    KeychainStore.save(password: legacyPassword, for: robot.id)
                }
                migratedRobots[index].password = nil

                KeychainStore.saveRobotConfig(migratedRobots[index], for: robot.id)
            }

            if let idsData = try? JSONEncoder().encode(decoded.map { $0.id }) {
                UserDefaults.standard.set(idsData, forKey: robotIdsKey)
            }

            UserDefaults.standard.removeObject(forKey: storageKey)

            loadedRobots = migratedRobots
        }

        robots = loadedRobots
        for robot in robots {
            apis[robot.id] = ValetudoAPI(config: robot)
        }
    }

    private func saveRobots() {
        for robot in robots {
            KeychainStore.saveRobotConfig(robot, for: robot.id)
        }
        // ID-Liste in UserDefaults (nur UUIDs, nicht sensibel)
        if let idsData = try? JSONEncoder().encode(robots.map { $0.id }) {
            UserDefaults.standard.set(idsData, forKey: robotIdsKey)
        }
    }
}

// MARK: - Robot Status
struct RobotStatus: Equatable {
    let isOnline: Bool
    let attributes: [RobotAttribute]
    let info: RobotInfo?

    init(isOnline: Bool, attributes: [RobotAttribute] = [], info: RobotInfo? = nil) {
        self.isOnline = isOnline
        self.attributes = attributes
        self.info = info
    }

    var batteryLevel: Int? {
        attributes.first { $0.__class == "BatteryStateAttribute" }?.level
    }

    var batteryStatus: String? {
        attributes.first { $0.__class == "BatteryStateAttribute" }?.flag
    }

    var statusValue: String? {
        attributes.first { $0.__class == "StatusStateAttribute" }?.value
    }

    var statusFlag: String? {
        attributes.first { $0.__class == "StatusStateAttribute" }?.flag
    }

    var cleanedArea: Int? {
        // Area in cm² from CurrentStatisticsAttribute
        if let areaAttr = attributes.first(where: { $0.__class == "LatestCleanupStatisticsAttribute" && $0.type == "area" }) {
            return areaAttr.value.flatMap { Int($0) }
        }
        return nil
    }

    // MARK: - Attachment States
    var dustbinAttached: Bool? {
        if let attr = attributes.first(where: { $0.__class == "AttachmentStateAttribute" && $0.type == "dustbin" }) {
            return attr.value == "true"
        }
        return nil
    }

    var mopAttached: Bool? {
        if let attr = attributes.first(where: { $0.__class == "AttachmentStateAttribute" && $0.type == "mop" }) {
            return attr.value == "true"
        }
        return nil
    }

    var waterTankAttached: Bool? {
        if let attr = attributes.first(where: { $0.__class == "AttachmentStateAttribute" && $0.type == "watertank" }) {
            return attr.value == "true"
        }
        return nil
    }

    // Returns true if any attachment is missing that the robot expects
    var hasMissingAttachments: Bool {
        // Only check attachments that the robot reports (not nil)
        if dustbinAttached == false { return true }
        if mopAttached == false { return true }
        if waterTankAttached == false { return true }
        return false
    }
}
