import Foundation
import AppKit

@MainActor
final class SyncManager: ObservableObject {
    @Published var syncStates: [UUID: SyncState] = [:]

    let store: ConfigStore
    private var timers: [UUID: Timer] = [:]
    private var watchers: [UUID: FileWatcher] = [:]
    private var runningProcesses: [UUID: Process] = [:]

    struct SyncState {
        var isRunning = false
        var log = ""
    }

    private var schedulesStarted = false

    init(store: ConfigStore) {
        self.store = store
    }

    func startAllOnce() {
        guard !schedulesStarted else { return }
        schedulesStarted = true
        startAll()
    }

    func startAll() {
        for config in store.configs {
            setupSchedule(for: config)
        }
    }

    func stopAll() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        watchers.values.forEach { $0.stop() }
        watchers.removeAll()
        let ids = Array(runningProcesses.keys)
        for id in ids {
            cancelSync(id: id)
        }
    }

    func refreshSchedules() {
        stopAll()
        startAll()
    }

    func setupSchedule(for config: SyncConfig) {
        timers[config.id]?.invalidate()
        timers.removeValue(forKey: config.id)
        watchers[config.id]?.stop()
        watchers.removeValue(forKey: config.id)

        switch config.schedule {
        case .manual:
            break
        case .interval(let minutes):
            let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncNow(id: config.id)
                }
            }
            timers[config.id] = timer
        case .onLocalChange:
            guard config.direction != .remoteToLocal else { return }
            let watcher = FileWatcher(path: config.localPath) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.syncNow(id: config.id)
                }
            }
            watcher.start()
            watchers[config.id] = watcher
        }
    }

    func teardownSchedule(for id: UUID) {
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
        watchers[id]?.stop()
        watchers.removeValue(forKey: id)
    }

    func state(for id: UUID) -> SyncState {
        syncStates[id] ?? SyncState()
    }

    func syncNow(id: UUID) {
        guard let config = store.configs.first(where: { $0.id == id }) else { return }
        runSync(config: config, dryRun: false)
    }

    func dryRun(config: SyncConfig) {
        runSync(config: config, dryRun: true)
    }

    private func runSync(config: SyncConfig, dryRun: Bool) {
        let id = config.id
        guard !(syncStates[id]?.isRunning ?? false) else { return }

        syncStates[id] = SyncState(isRunning: true, log: dryRun ? "=== DRY RUN ===\n" : "")

        let rclone = RcloneService(rclonePath: store.settings.rclonePath)
        Task {
            var success = false
            do {
                try await rclone.sync(
                    config: config,
                    dryRun: dryRun,
                    onProcess: { [weak self] process in
                        Task { @MainActor [weak self] in
                            self?.runningProcesses[id] = process
                        }
                    },
                    onOutput: { [weak self] output in
                        Task { @MainActor [weak self] in
                            self?.syncStates[id]?.log.append(output)
                        }
                    }
                )
                success = true
            } catch {
                await MainActor.run {
                    self.syncStates[id]?.log.append("\nError: \(error.localizedDescription)\n")
                }
            }
            await MainActor.run {
                self.finishSync(id: id, success: success, dryRun: dryRun)
            }
        }
    }

    private func finishSync(id: UUID, success: Bool, dryRun: Bool) {
        runningProcesses.removeValue(forKey: id)
        syncStates[id]?.isRunning = false
        guard !dryRun, let i = store.configs.firstIndex(where: { $0.id == id }) else { return }
        store.configs[i].lastSyncDate = Date()
        store.configs[i].lastSyncSuccess = success
        store.saveConfigs()
    }

    func cancelSync(id: UUID) {
        if let process = runningProcesses.removeValue(forKey: id), process.isRunning {
            process.terminate()
        }
        syncStates[id]?.isRunning = false
        syncStates[id]?.log.append("\n--- Cancelled ---\n")
    }

    func revealBackups(id: UUID) {
        let dir = ConfigStore.backupsDir.appendingPathComponent(id.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}
