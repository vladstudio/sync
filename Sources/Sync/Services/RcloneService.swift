import Foundation

struct RcloneService: Sendable {
    let rclonePath: String

    init(rclonePath: String = "/opt/homebrew/bin/rclone") {
        self.rclonePath = rclonePath
    }

    func listRemotes() async throws -> [String] {
        try checkBinary()
        let output = try await run(arguments: ["listremotes"])
        return output.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .map { $0.hasSuffix(":") ? String($0.dropLast()) : $0 }
            .filter { !$0.isEmpty }
    }

    func buildArguments(config: SyncConfig, dryRun: Bool = false) -> [String] {
        let remoteFull = "\(config.remote):\(config.remotePath)"
        var args: [String] = []

        switch config.direction {
        case .bidirectional:
            args = ["bisync", config.localPath, remoteFull]
        case .localToRemote:
            args = [config.mode.rawValue, config.localPath, remoteFull]
        case .remoteToLocal:
            args = [config.mode.rawValue, remoteFull, config.localPath]
        }

        args += ["--checksum", "--progress"]
        if config.direction != .bidirectional {
            args.append("--update")
        }

        if config.keepDeletedFiles {
            let ts = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backupDir = ConfigStore.backupsDir
                .appendingPathComponent(config.id.uuidString)
                .appendingPathComponent(ts)
                .path
            args += ["--backup-dir", backupDir]
        }

        if let bw = config.bandwidthLimit, !bw.isEmpty {
            args += ["--bwlimit", bw]
        }

        for pattern in config.excludePatterns where !pattern.isEmpty {
            args += ["--exclude", pattern]
        }

        if !config.extraFlags.isEmpty {
            let extra = config.extraFlags.split(separator: " ").map(String.init)
            args += extra
        }

        if dryRun {
            args.append("--dry-run")
        }

        return args
    }

    /// Runs sync. Calls `onProcess` with the Process immediately after launch (before it finishes)
    /// so callers can store it for cancellation.
    func sync(
        config: SyncConfig,
        dryRun: Bool = false,
        onProcess: @Sendable @escaping (Process) -> Void,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws {
        try checkBinary()
        let arguments = buildArguments(config: config, dryRun: dryRun)
        try await runStreaming(arguments: arguments, onProcess: onProcess, onOutput: onOutput)
    }

    private func run(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: rclonePath)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { p in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if p.terminationStatus != 0 {
                    continuation.resume(throwing: RcloneError.failed(output))
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runStreaming(
        arguments: [String],
        onProcess: @Sendable @escaping (Process) -> Void,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: rclonePath)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                    onOutput(str)
                }
            }

            process.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus != 0 {
                    continuation.resume(throwing: RcloneError.exitCode(Int(p.terminationStatus)))
                } else {
                    continuation.resume()
                }
            }

            do {
                try process.run()
                onProcess(process)
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func checkBinary() throws {
        guard FileManager.default.isExecutableFile(atPath: rclonePath) else {
            throw RcloneError.notInstalled(rclonePath)
        }
    }

    enum RcloneError: Error, LocalizedError {
        case notInstalled(String)
        case failed(String)
        case exitCode(Int)

        var errorDescription: String? {
            switch self {
            case .notInstalled(let path): "rclone not found at \(path). Install it or update the path in Settings."
            case .failed(let msg): msg
            case .exitCode(let code): "rclone exited with code \(code)"
            }
        }
    }
}
