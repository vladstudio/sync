import Foundation

@MainActor
final class ConfigStore: ObservableObject {
    @Published var configs: [SyncConfig] = []
    @Published var settings: AppSettings = AppSettings()
    @Published var configError: String?
    @Published var settingsError: String?

    var lastError: String? {
        get {
            let parts = [configError, settingsError].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
        set {
            configError = newValue
            settingsError = nil
        }
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    nonisolated static let appSupportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    nonisolated static let backupsDir: URL = {
        let dir = appSupportDir.appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    nonisolated static let logsDir: URL = {
        let dir = appSupportDir.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var configURL: URL { Self.appSupportDir.appendingPathComponent("config.json") }
    private var settingsURL: URL { Self.appSupportDir.appendingPathComponent("settings.json") }

    func load() {
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                configs = try decoder.decode([SyncConfig].self, from: data)
                configError = nil
            } catch {
                configError = "Failed to load configs: \(error.localizedDescription)"
            }
        }

        if FileManager.default.fileExists(atPath: settingsURL.path) {
            do {
                let data = try Data(contentsOf: settingsURL)
                settings = try decoder.decode(AppSettings.self, from: data)
                settingsError = nil
            } catch {
                settingsError = "Failed to load settings: \(error.localizedDescription)"
            }
        }
    }

    func saveConfigs() {
        do {
            let data = try encoder.encode(configs)
            try data.write(to: configURL, options: .atomic)
            configError = nil
        } catch {
            configError = "Failed to save configs: \(error.localizedDescription)"
        }
    }

    func saveSettings() {
        do {
            let data = try encoder.encode(settings)
            try data.write(to: settingsURL, options: .atomic)
            settingsError = nil
        } catch {
            settingsError = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    func addConfig(_ config: SyncConfig) {
        configs.append(config)
        saveConfigs()
    }

    func updateConfig(_ config: SyncConfig) {
        if let i = configs.firstIndex(where: { $0.id == config.id }) {
            configs[i] = config
            saveConfigs()
        }
    }

    func deleteConfig(id: UUID) {
        configs.removeAll { $0.id == id }
        saveConfigs()
    }
}
