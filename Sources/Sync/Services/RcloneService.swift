import Foundation

struct RcloneService: Sendable {
    let rclonePath: String

    init(rclonePath: String = "/opt/homebrew/bin/rclone") {
        self.rclonePath = rclonePath
    }

    func listRemotes() async throws -> [String] {
        let output = try await run(arguments: ["listremotes"])
        return output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingSuffix(":") }
            .map(String.init)
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

        args += ["--checksum", "--update", "--progress"]

        if config.keepDeletedFiles {
            let ts = ISO8601DateFormatter().string(from: Date())
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

    /// Runs sync and returns the Process so callers can terminate it.
    func sync(config: SyncConfig, dryRun: Bool = false, onOutput: @Sendable @escaping (String) -> Void) async throws -> Process {
        let arguments = buildArguments(config: config, dryRun: dryRun)
        return try await runStreaming(arguments: arguments, onOutput: onOutput)
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

    @discardableResult
    private func runStreaming(arguments: [String], onOutput: @Sendable @escaping (String) -> Void) async throws -> Process {
        let process = Process()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
        return process
    }

    enum RcloneError: Error, LocalizedError {
        case failed(String)
        case exitCode(Int)

        var errorDescription: String? {
            switch self {
            case .failed(let msg): msg
            case .exitCode(let code): "rclone exited with code \(code)"
            }
        }
    }
}

private extension Substring {
    func trimmingSuffix(_ suffix: Character) -> Substring {
        if last == suffix { return dropLast() }
        return self
    }
}
