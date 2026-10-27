import SwiftUI
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.valetudio", category: "AutoEmptyDockSettingsView")

// MARK: - Auto Empty Dock Settings View
struct AutoEmptyDockSettingsView: View {
    let robot: RobotConfig
    @Environment(RobotManager.self) var robotManager

    @State private var presets: [String] = []
    @State private var selectedPreset: String?
    @State private var isLoading = false

    private var api: ValetudoAPI? {
        robotManager.getAPI(for: robot.id)
    }

    var body: some View {
        List {
            if presets.isEmpty && !isLoading {
                Text(String(localized: "settings.no_presets"))
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            Task { await selectPreset(preset) }
                        } label: {
                            HStack {
                                Text(displayNameForInterval(preset))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedPreset == preset {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } footer: {
                    Text(String(localized: "settings.auto_empty_interval_desc"))
                }
            }
        }
        .navigationTitle(String(localized: "settings.auto_empty_interval"))
        .task {
            await loadPresets()
        }
        .overlay {
            if isLoading && presets.isEmpty {
                ProgressView()
            }
        }
    }

    private func loadPresets() async {
        guard let api = api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            presets = try await api.getAutoEmptyDockIntervalPresets()
            // Mark the robot's current value before anything is changed.
            selectedPreset = (try? await api.getAutoEmptyDockInterval()) ?? selectedPreset
        } catch {
            logger.error("Failed to load auto empty dock presets: \(error, privacy: .public)")
        }
    }

    /// The firmware reports "off", "infrequent", "normal" or "frequent".
    private func displayNameForInterval(_ preset: String) -> String {
        switch preset.lowercased() {
        case "off":
            return String(localized: "empty_interval.off")
        case "infrequent":
            return String(localized: "empty_interval.infrequent")
        case "normal":
            return String(localized: "empty_interval.normal")
        case "frequent":
            return String(localized: "empty_interval.frequent")
        default:
            return preset.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }
    }

    private func selectPreset(_ preset: String) async {
        guard let api = api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await api.setAutoEmptyDockInterval(preset: preset)
            selectedPreset = preset
        } catch {
            logger.error("Failed to set auto empty dock preset: \(error, privacy: .public)")
        }
    }
}
