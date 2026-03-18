import Foundation
import AppKit
@preconcurrency import UserNotifications

/// Collects rapid output and flushes at most every 200ms to avoid flooding the main thread.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var pendingBytes = 0
    private var lastFlush = Date.distantPast
    private let interval: TimeInterval = 0.2
    private let maxSize = 512 * 1024 // 512 KB

    func append(_ text: String) {
        lock.lock()
        if pendingBytes < maxSize {
            pending.append(text)
            pendingBytes += text.utf8.count
        }
        lock.unlock()
    }

    func flushThrottled(_ handler: (String) -> Void) {
        lock.lock()
        let now = Date()
        guard now.timeIntervalSince(lastFlush) >= interval, !pending.isEmpty else {
            lock.unlock()
            return
        }
        let flushed = pending
        pending = ""
        pendingBytes = 0
        lastFlush = now
        lock.unlock()
        handler(flushed)
    }

    func drain() -> String {
        lock.lock()
        let flushed = pending
        pending = ""
        pendingBytes = 0
        lock.unlock()
        return flushed
    }
}

@MainActor
final class SyncManager: ObservableObject {
    @Published var syncStates: [UUID: SyncState] = [:]

    let store: ConfigStore
    private var timers: [UUID: Timer] = [:]
    private var watchers: [UUID: FileWatcher] = [:]
    private var runningProcesses: [UUID: Process] = [:]
    private var cancelledSyncs: Set<UUID> = []
    private var notificationAuthorized: Bool?

    struct SyncState {
        var isRunning = false
        var log = ""
    }

    private enum SyncOutcome {
        case success
        case failure
        case cancelled
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

    func setupSchedule(for config: SyncConfig) {
        timers[config.id]?.invalidate()
        timers.removeValue(forKey: config.id)
        watchers[config.id]?.stop()
        watchers.removeValue(forKey: config.id)

        switch config.schedule {
        case .manual:
            break
        case .interval(let minutes):
            syncNow(id: config.id)
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

    private var syncGeneration: [UUID: Int] = [:]

    private func runSync(config: SyncConfig, dryRun: Bool) {
        let id = config.id
        guard !(syncStates[id]?.isRunning ?? false) else { return }

        cancelledSyncs.remove(id)
        let gen = (syncGeneration[id] ?? 0) + 1
        syncGeneration[id] = gen
        syncStates[id] = SyncState(isRunning: true, log: dryRun ? "=== DRY RUN ===\n" : "")

        let rclone = RcloneService(rclonePath: store.settings.rclonePath)
        Task {
            let (outcome, remaining) = await self.executeSync(id: id, config: config, dryRun: dryRun, rclone: rclone)
            await MainActor.run {
                // Skip if a newer sync has started for this id (cancel + re-sync race)
                guard self.syncGeneration[id] == gen else { return }
                if !remaining.isEmpty {
                    self.syncStates[id]?.log.append(remaining)
                }
                self.finishSync(id: id, outcome: outcome, dryRun: dryRun)
            }
        }
    }

    private func executeSync(
        id: UUID, config: SyncConfig, dryRun: Bool, rclone: RcloneService, retried: Bool = false
    ) async -> (SyncOutcome, String) {
        let buffer = OutputBuffer()
        var outcome: SyncOutcome = .failure
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
                    buffer.append(output)
                    buffer.flushThrottled { flushed in
                        Task { @MainActor [weak self] in
                            self?.syncStates[id]?.log.append(flushed)
                        }
                    }
                }
            )
            outcome = .success
        } catch {
            let wasCancelled = await MainActor.run { self.cancelledSyncs.contains(id) }
            if wasCancelled {
                outcome = .cancelled
            } else {
                let log = buffer.drain()
                // Retry once after removing a stale bisync lock file
                if !retried, let lockPath = Self.parseLockPath(from: log) {
                    try? FileManager.default.removeItem(atPath: lockPath)
                    await MainActor.run {
                        self.syncStates[id]?.log.append(log)
                        self.syncStates[id]?.log.append("\n--- Removed stale lock file, retrying ---\n\n")
                    }
                    return await executeSync(id: id, config: config, dryRun: dryRun, rclone: rclone, retried: true)
                }
                await MainActor.run {
                    self.syncStates[id]?.log.append(log)
                    self.syncStates[id]?.log.append("\nError: \(error.localizedDescription)\n")
                }
            }
        }
        return (outcome, buffer.drain())
    }

    private static func parseLockPath(from log: String) -> String? {
        guard let marker = log.range(of: "prior lock file found: ") else { return nil }
        let rest = log[marker.upperBound...]
        let path = String(rest.prefix(while: { !$0.isNewline }))
            .trimmingCharacters(in: .whitespaces)
        guard path.hasSuffix(".lck") else { return nil }
        return path
    }

    private func finishSync(id: UUID, outcome: SyncOutcome, dryRun: Bool) {
        runningProcesses.removeValue(forKey: id)
        syncStates[id]?.isRunning = false
        defer { cancelledSyncs.remove(id) }
        guard let i = store.configs.firstIndex(where: { $0.id == id }) else { return }
        guard outcome != .cancelled else { return }

        if dryRun {
            if outcome == .success { store.configs[i].lastSyncSuccess = true }
        } else {
            // For bidirectional, only set lastSyncDate on success — a nil lastSyncDate
            // triggers --resync which is required to establish the baseline listing files.
            if outcome == .success || store.configs[i].direction != .bidirectional {
                store.configs[i].lastSyncDate = Date()
            }
            store.configs[i].lastSyncSuccess = (outcome == .success)
        }
        store.saveConfigs()

        if !dryRun, outcome == .failure {
            postFailureNotification(name: store.configs[i].name)
        }
    }

    private func postFailureNotification(name: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            if notificationAuthorized == nil {
                notificationAuthorized = (try? await center.requestAuthorization(options: [.alert])) ?? false
            }
            guard notificationAuthorized == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Sync Failed"
            content.body = name
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    func cancelSync(id: UUID) {
        cancelledSyncs.insert(id)
        if let process = runningProcesses.removeValue(forKey: id), process.isRunning {
            process.interrupt()
        }
        if syncStates[id]?.isRunning == true {
            syncStates[id]?.log.append("\n--- Cancelled ---\n")
        }
        syncStates[id]?.isRunning = false
    }

    func revealBackups(id: UUID) {
        let dir = ConfigStore.backupsDir.appendingPathComponent(id.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func cleanupBackups(config: SyncConfig) async throws {
        let localDir = ConfigStore.backupsDir.appendingPathComponent(config.id.uuidString)
        var errors: [String] = []

        if FileManager.default.fileExists(atPath: localDir.path) {
            do {
                try FileManager.default.removeItem(at: localDir)
            } catch {
                errors.append("Failed to delete local backups: \(error.localizedDescription)")
            }
        }

        if !config.remote.isEmpty {
            let rclone = RcloneService(rclonePath: store.settings.rclonePath)
            let remotePath = "\(config.remote):.rclone-backup/\(config.id.uuidString)"
            do {
                try await rclone.purge(path: remotePath)
            } catch {
                errors.append("Failed to delete remote backups: \(error.localizedDescription)")
            }
        }

        if !errors.isEmpty {
            throw CleanupError.failed(errors)
        }
    }

    enum CleanupError: LocalizedError {
        case failed([String])

        var errorDescription: String? {
            switch self {
            case .failed(let errors):
                errors.joined(separator: "\n")
            }
        }
    }
}
