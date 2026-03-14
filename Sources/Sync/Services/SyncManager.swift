import Foundation
import SwiftUI
import AppKit

@MainActor
final class SyncManager: ObservableObject {
    @Published var syncStates: [UUID: SyncState] = [:]

    let store: ConfigStore
    private var timers: [UUID: Timer] = [:]
    private var watchers: [UUID: FileWatcher] = [:]
    private var processes: [UUID: Task<Void, Never>] = [:]

    struct SyncState {
        var isRunning = false
        var log = ""
        var lastRunDate: Date?
        var lastSuccess: Bool?
    }

    init(store: ConfigStore) {
        self.store = store
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
        processes.values.forEach { $0.cancel() }
        processes.removeAll()
    }

    func refreshSchedules() {
        stopAll()
        startAll()
    }

    func setupSchedule(for config: SyncConfig) {
        // Clear existing
        timers[config.id]?.invalidate()
        watchers[config.id]?.stop()

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

    func state(for id: UUID) -> SyncState {
        syncStates[id] ?? SyncState()
    }

    func syncNow(id: UUID, dryRun: Bool = false) {
        guard let config = store.configs.first(where: { $0.id == id }) else { return }
        guard !(syncStates[id]?.isRunning ?? false) else { return }

        syncStates[id] = SyncState(isRunning: true, log: dryRun ? "=== DRY RUN ===\n" : "")

        let rclone = RcloneService(rclonePath: store.settings.rclonePath)
        let task = Task {
            do {
                try await rclone.sync(config: config, dryRun: dryRun) { [weak self] output in
                    Task { @MainActor [weak self] in
                        self?.syncStates[id]?.log.append(output)
                    }
                }
                await MainActor.run {
                    self.syncStates[id]?.isRunning = false
                    self.syncStates[id]?.lastRunDate = Date()
                    self.syncStates[id]?.lastSuccess = true
                    if !dryRun {
                        if let i = self.store.configs.firstIndex(where: { $0.id == id }) {
                            self.store.configs[i].lastSyncDate = Date()
                            self.store.configs[i].lastSyncSuccess = true
                            self.store.saveConfigs()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.syncStates[id]?.log.append("\nError: \(error.localizedDescription)\n")
                    self.syncStates[id]?.isRunning = false
                    self.syncStates[id]?.lastRunDate = Date()
                    self.syncStates[id]?.lastSuccess = false
                    if !dryRun {
                        if let i = self.store.configs.firstIndex(where: { $0.id == id }) {
                            self.store.configs[i].lastSyncDate = Date()
                            self.store.configs[i].lastSyncSuccess = false
                            self.store.saveConfigs()
                        }
                    }
                }
            }
        }
        processes[id] = task
    }

    func cancelSync(id: UUID) {
        processes[id]?.cancel()
        processes[id] = nil
        syncStates[id]?.isRunning = false
        syncStates[id]?.log.append("\n--- Cancelled ---\n")
    }

    func revealBackups(id: UUID) {
        let dir = ConfigStore.backupsDir.appendingPathComponent(id.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}
