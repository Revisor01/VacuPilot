import SwiftUI
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.valetudio", category: "StationSettingsView")

// MARK: - Station Settings View (Dock/Station specific settings)
struct StationSettingsView: View {
    let robot: RobotConfig
    @Environment(RobotManager.self) var robotManager

    @State private var isLoading = false
    @State private var stationLoaded = false

    // Capabilities
    @State private var hasAutoEmptyDock = DebugConfig.showAllCapabilities
    @State private var hasAutoEmptyDockDuration = DebugConfig.showAllCapabilities
    @State private var hasMopDockAutoDrying = DebugConfig.showAllCapabilities
    @State private var hasMopDockWashTemperature = DebugConfig.showAllCapabilities
    @State private var hasMopDockDryingTime = DebugConfig.showAllCapabilities

    // Settings
    @State private var mopDockAutoDrying = false
    @State private var mopDockWashTemperaturePresets: [String] = []
    @State private var currentWashTemperature: String = ""
    @State private var mopDockDryingTimePresets: [String] = []
    @State private var currentMopDockDryingTime: String = ""
    @State private var autoEmptyDockDurationPresets: [String] = []
    @State private var currentAutoEmptyDockDuration: String = ""

    private var api: ValetudoAPI? {
        robotManager.getAPI(for: robot.id)
    }

    var body: some View {
        List {
            // Auto Empty Dock Settings
            if hasAutoEmptyDock || hasAutoEmptyDockDuration {
                Section {
                    if hasAutoEmptyDock {
                        NavigationLink {
                            AutoEmptyDockSettingsView(robot: robot)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.bin")
                                    .foregroundStyle(.purple)
                                Text(String(localized: "settings.auto_empty_interval"))
                            }
                        }
                    }

                    if hasAutoEmptyDockDuration && !autoEmptyDockDurationPresets.isEmpty {
                        Picker(selection: $currentAutoEmptyDockDuration) {
                            ForEach(autoEmptyDockDurationPresets, id: \.self) { preset in
                                Text(displayNameForAutoEmptyDockDuration(preset)).tag(preset)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "timer")
                                    .foregroundStyle(.purple)
                                Text(String(localized: "auto_empty.duration_label"))
                            }
                        }
                        .onChange(of: currentAutoEmptyDockDuration) { _, newValue in
                            guard stationLoaded && !newValue.isEmpty else { return }
                            Task { await setAutoEmptyDockDuration(newValue) }
                        }
                    }
                } header: {
                    Label(String(localized: "settings.auto_empty"), systemImage: "arrow.up.bin")
                } footer: {
                    Text(String(localized: "settings.auto_empty_interval_desc"))
                }
            }

            // Mop Dock Settings
            if hasMopDockAutoDrying || hasMopDockWashTemperature || hasMopDockDryingTime {
                Section {
                    if hasMopDockAutoDrying {
                        Toggle(isOn: $mopDockAutoDrying) {
                            HStack {
                                Image(systemName: "wind")
                                    .foregroundStyle(.cyan)
                                Text(String(localized: "settings.mop_auto_drying"))
                            }
                        }
                        .onChange(of: mopDockAutoDrying) { _, newValue in
                            guard stationLoaded else { return }
                            Task { await setMopDockAutoDrying(newValue) }
                        }
                    }

                    if hasMopDockWashTemperature {
                        Picker(selection: $currentWashTemperature) {
                            ForEach(mopDockWashTemperaturePresets.isEmpty ? ["cold", "warm", "hot"] : mopDockWashTemperaturePresets, id: \.self) { preset in
                                Text(displayNameForWashTemperature(preset)).tag(preset)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "thermometer.medium")
                                    .foregroundStyle(.orange)
                                Text(String(localized: "settings.wash_temperature"))
                            }
                        }
                        .onChange(of: currentWashTemperature) { _, newValue in
                            guard stationLoaded && !newValue.isEmpty else { return }
                            Task { await setWashTemperature(newValue) }
                        }
                    }

                    if hasMopDockDryingTime && !mopDockDryingTimePresets.isEmpty {
                        Picker(selection: $currentMopDockDryingTime) {
                            ForEach(mopDockDryingTimePresets, id: \.self) { preset in
                                Text(displayNameForDryingTime(preset)).tag(preset)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "fan")
                                    .foregroundStyle(.cyan)
                                Text(String(localized: "mop_dock.drying_time_label"))
                            }
                        }
                        .onChange(of: currentMopDockDryingTime) { _, newValue in
                            guard stationLoaded && !newValue.isEmpty else { return }
                            Task { await setDryingTime(newValue) }
                        }
                    }
                } header: {
                    Label(String(localized: "settings.mop_dock"), systemImage: "drop.triangle")
                } footer: {
                    Text(String(localized: "settings.dock_settings_desc"))
                }
            }

            // No settings available
            if !hasAutoEmptyDock && !hasAutoEmptyDockDuration && !hasMopDockAutoDrying && !hasMopDockWashTemperature && !hasMopDockDryingTime && !isLoading {
                Section {
                    Text(String(localized: "settings.no_station_settings"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: "settings.section_station"))
        .task {
            await loadSettings()
        }
        .refreshable {
            await loadSettings()
        }
        .overlay {
            if isLoading && !hasAutoEmptyDock && !hasAutoEmptyDockDuration && !hasMopDockAutoDrying && !hasMopDockWashTemperature && !hasMopDockDryingTime {
                ProgressView()
            }
        }
    }

    private func loadSettings() async {
        guard let api = api else { return }
        stationLoaded = false
        isLoading = true
        defer { isLoading = false }

        // Check capabilities
        do {
            let capabilities = try await api.getCapabilities()
            hasAutoEmptyDock = DebugConfig.showAllCapabilities || capabilities.contains("AutoEmptyDockAutoEmptyIntervalControlCapability")
            hasAutoEmptyDockDuration = DebugConfig.showAllCapabilities || capabilities.contains("AutoEmptyDockAutoEmptyDurationControlCapability")
            hasMopDockAutoDrying = DebugConfig.showAllCapabilities || capabilities.contains("MopDockMopAutoDryingControlCapability")
            hasMopDockWashTemperature = DebugConfig.showAllCapabilities || capabilities.contains("MopDockMopWashTemperatureControlCapability")
            hasMopDockDryingTime = DebugConfig.showAllCapabilities || capabilities.contains("MopDockMopDryingTimeControlCapability")
        } catch {
            // Use debug defaults
        }

        // Load mop dock auto drying
        if hasMopDockAutoDrying {
            do {
                mopDockAutoDrying = try await api.getMopDockAutoDrying()
            } catch {
                if !DebugConfig.showAllCapabilities { hasMopDockAutoDrying = false }
            }
        }

        // Load mop dock wash temperature presets
        if hasMopDockWashTemperature {
            do {
                mopDockWashTemperaturePresets = try await api.getMopDockWashTemperaturePresets()
                // The capability reports its own current value; there is no
                // matching state attribute for it.
                currentWashTemperature = (try? await api.getMopDockWashTemperature()) ?? ""
                if currentWashTemperature.isEmpty, let first = mopDockWashTemperaturePresets.first {
                    currentWashTemperature = first
                }
            } catch {
                if !DebugConfig.showAllCapabilities { hasMopDockWashTemperature = false }
                // Use debug defaults
                if DebugConfig.showAllCapabilities {
                    mopDockWashTemperaturePresets = ["cold", "warm", "hot"]
                    currentWashTemperature = "warm"
                }
            }
        }

        // Load mop dock drying time presets
        if hasMopDockDryingTime {
            do {
                mopDockDryingTimePresets = try await api.getMopDockDryingTimePresets()
                currentMopDockDryingTime = (try? await api.getMopDockDryingTime()) ?? ""
                if currentMopDockDryingTime.isEmpty, let first = mopDockDryingTimePresets.first {
                    currentMopDockDryingTime = first
                }
            } catch {
                if !DebugConfig.showAllCapabilities { hasMopDockDryingTime = false }
                mopDockDryingTimePresets = []
                logger.debug("Mop dock drying time not supported: \(error, privacy: .public)")
            }
        }

        // Load auto empty dock duration presets
        if hasAutoEmptyDockDuration {
            do {
                autoEmptyDockDurationPresets = try await api.getAutoEmptyDockDurationPresets()
                currentAutoEmptyDockDuration = (try? await api.getAutoEmptyDockDuration()) ?? ""
                if currentAutoEmptyDockDuration.isEmpty, let first = autoEmptyDockDurationPresets.first {
                    currentAutoEmptyDockDuration = first
                }
            } catch {
                if !DebugConfig.showAllCapabilities { hasAutoEmptyDockDuration = false }
                autoEmptyDockDurationPresets = []
                logger.debug("Auto empty dock duration not supported: \(error, privacy: .public)")
            }
        }

        stationLoaded = true
    }

    private func setMopDockAutoDrying(_ enabled: Bool) async {
        guard let api = api else { return }

        do {
            try await api.setMopDockAutoDrying(enabled: enabled)
        } catch {
            logger.error("Failed to set mop dock auto drying: \(error, privacy: .public)")
            mopDockAutoDrying = !enabled
        }
    }

    private func setWashTemperature(_ preset: String) async {
        guard let api = api else { return }

        do {
            try await api.setMopDockWashTemperature(preset: preset)
        } catch {
            logger.error("Failed to set wash temperature: \(error, privacy: .public)")
        }
    }

    private func setDryingTime(_ preset: String) async {
        guard let api = api else { return }

        do {
            try await api.setMopDockDryingTime(preset: preset)
        } catch {
            logger.error("Failed to set mop dock drying time: \(error, privacy: .public)")
        }
    }

    private func displayNameForWashTemperature(_ preset: String) -> String {
        switch preset.lowercased() {
        case "cold":
            return String(localized: "settings.wash_temp.cold")
        case "warm":
            return String(localized: "settings.wash_temp.warm")
        case "hot":
            return String(localized: "settings.wash_temp.hot")
        case "scalding":
            return String(localized: "settings.wash_temp.scalding")
        case "boiling":
            return String(localized: "settings.wash_temp.boiling")
        default:
            return humanized(preset)
        }
    }

    /// Last resort for values this build does not know: readable, not raw.
    private func humanized(_ preset: String) -> String {
        preset.replacingOccurrences(of: "_", with: " ").localizedCapitalized
    }

    /// Drying time is reported as "2h", "3h", "4h" or "cold" — not as words.
    private func displayNameForDryingTime(_ preset: String) -> String {
        switch preset.lowercased() {
        case "2h":
            return String(localized: "drying_time.2h")
        case "3h":
            return String(localized: "drying_time.3h")
        case "4h":
            return String(localized: "drying_time.4h")
        case "cold":
            return String(localized: "drying_time.cold")
        default:
            return humanized(preset)
        }
    }

    private func setAutoEmptyDockDuration(_ preset: String) async {
        guard let api = api else { return }
        do {
            try await api.setAutoEmptyDockDuration(preset: preset)
        } catch {
            logger.error("Failed to set auto empty dock duration: \(error, privacy: .public)")
        }
    }

    /// The firmware reports "auto", "short", "medium" or "long" here — the
    /// intensity names used elsewhere do not apply.
    private func displayNameForAutoEmptyDockDuration(_ preset: String) -> String {
        switch preset.lowercased() {
        case "auto":
            return String(localized: "empty_duration.auto")
        case "short":
            return String(localized: "empty_duration.short")
        case "medium":
            return String(localized: "empty_duration.medium")
        case "long":
            return String(localized: "empty_duration.long")
        default:
            return humanized(preset)
        }
    }
}
