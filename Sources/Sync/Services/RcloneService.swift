import Foundation

struct RcloneService: Sendable {
    let rclonePath: String

    init(rclonePath: String = "/opt/homebrew/bin/rclone") {
        self.rclonePath = rclonePath
    }

    struct RemoteInfo: Sendable, Identifiable {
        var id: String { name }
        let name: String
        let type: String
    }

    func listRemotes() async throws -> [RemoteInfo] {
        try checkBinary()
        let output = try await run(arguments: ["listremotes", "--long"])
        return output.split(separator: "\n")
            .compactMap { line -> RemoteInfo? in
                let str = String(line)
                guard let colon = str.firstIndex(of: ":") else { return nil }
                let name = str[str.startIndex..<colon].trimmingCharacters(in: .whitespaces)
                let type = str[str.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
                return RemoteInfo(name: name, type: type)
            }
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

        args += ["--checksum", "-v", "--stats-one-line-date", "--stats", "2s"]
        if config.direction == .bidirectional {
            if config.lastSyncSuccess != true {
                args.append("--resync")
            }
        } else {
            args.append("--update")
        }

        if config.keepDeletedFiles {
            let ts = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let localBackupDir = ConfigStore.backupsDir
                .appendingPathComponent(config.id.uuidString)
                .appendingPathComponent(ts)
                .path
            let remoteBackupDir = "\(config.remote):.rclone-backup/\(ts)"
            if config.direction == .bidirectional {
                args += ["--backup-dir1", localBackupDir, "--backup-dir2", remoteBackupDir]
            } else if config.direction == .localToRemote {
                args += ["--backup-dir", remoteBackupDir]
            } else {
                args += ["--backup-dir", localBackupDir]
            }
        }

        if let bw = config.bandwidthLimit, !bw.isEmpty {
            args += ["--bwlimit", bw]
        }

        for pattern in config.excludePatterns where !pattern.isEmpty {
            args += ["--exclude", pattern]
        }

        if !config.extraFlags.isEmpty {
            args += shellSplit(config.extraFlags)
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
                    let clean = str.replacingOccurrences(
                        of: "\\x1B\\[[0-9;]*m",
                        with: "",
                        options: .regularExpression
                    )
                    onOutput(clean)
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

    func purge(path: String) async throws {
        try checkBinary()
        _ = try await run(arguments: ["purge", path])
    }

    func link(remotePath: String) async throws -> URL? {
        try checkBinary()
        let output = try await run(arguments: ["link", remotePath])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed)
    }

    func version() async throws -> String {
        try checkBinary()
        let output = try await run(arguments: ["version"])
        if let firstLine = output.split(separator: "\n").first {
            return String(firstLine)
        }
        return "rclone found"
    }

    private func shellSplit(_ s: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inDouble = false
        var inSingle = false
        for ch in s {
            if ch == "\"" && !inSingle {
                inDouble.toggle()
            } else if ch == "'" && !inDouble {
                inSingle.toggle()
            } else if ch == " " && !inDouble && !inSingle {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { args.append(current) }
        return args
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
            case .exitCode(let code): "rclone failed: \(Self.exitCodeDescription(code)) (exit code \(code))"
            }
        }
        private static func exitCodeDescription(_ code: Int) -> String {
            switch code {
            case 1: return "syntax or usage error"
            case 2: return "error not otherwise categorised"
            case 3: return "directory not found"
            case 4: return "file not found"
            case 5: return "temporary error, retries exhausted"
            case 6: return "some files failed to transfer"
            case 7: return "fatal error"
            case 8: return "transfer limit reached"
            case 9: return "no files transferred"
            default: return "unknown error"
            }
        }
    }
}
