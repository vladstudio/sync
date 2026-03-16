import Foundation

struct RcloneService: Sendable {
    let rclonePath: String

    init(rclonePath: String = "/opt/homebrew/bin/rclone") {
        self.rclonePath = rclonePath
    }

    struct RemoteInfo: Sendable, Identifiable, Equatable {
        var id: String { name }
        let name: String
        let type: String
    }

    enum ArgumentParsingError: Error, LocalizedError, Equatable {
        case danglingEscape
        case unterminatedSingleQuote
        case unterminatedDoubleQuote

        var errorDescription: String? {
            switch self {
            case .danglingEscape:
                "Extra flags end with an incomplete escape sequence."
            case .unterminatedSingleQuote:
                "Extra flags contain an unterminated single-quoted string."
            case .unterminatedDoubleQuote:
                "Extra flags contain an unterminated double-quoted string."
            }
        }
    }

    private enum QuoteState {
        case single
        case double
    }

    func listRemotes() async throws -> [RemoteInfo] {
        try checkBinary()
        let output = try await run(arguments: ["listremotes", "--long"])
        return Self.parseRemotesOutput(output)
    }

    static func parseRemotesOutput(_ output: String) -> [RemoteInfo] {
        output.split(separator: "\n")
            .compactMap { line -> RemoteInfo? in
                let str = String(line)
                guard let colon = str.firstIndex(of: ":") else { return nil }
                let name = str[str.startIndex..<colon].trimmingCharacters(in: .whitespaces)
                let type = str[str.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, !type.isEmpty else { return nil }
                return RemoteInfo(name: name, type: type)
            }
    }

    func buildArguments(config: SyncConfig, dryRun: Bool = false) throws -> [String] {
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

        args += ["-v", "--stats-one-line-date", "--stats", "2s", "--color", "NEVER", "--retries-sleep", "10s"]
        if config.direction == .bidirectional {
            args += ["--max-lock", "2m", "--resilient", "--recover", "--conflict-resolve", "newer"]
            if config.lastSyncDate == nil {
                args.append("--resync")
            }
        } else {
            args += ["--update", "--check-first", "--fast-list"]
            if config.mode == .sync {
                args.append("--track-renames")
            }
        }

        if config.keepDeletedFiles {
            let ts = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let localBackupDir = ConfigStore.backupsDir
                .appendingPathComponent(config.id.uuidString)
                .appendingPathComponent(ts)
                .path
            let remoteBackupDir = "\(config.remote):.rclone-backup/\(config.id.uuidString)/\(ts)"
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
            args += try splitCommandLine(config.extraFlags)
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
        let arguments = try buildArguments(config: config, dryRun: dryRun)
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
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty, let str = String(data: remaining, encoding: .utf8) {
                    onOutput(str)
                }
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

    private func splitCommandLine(_ s: String) throws -> [String] {
        var args: [String] = []
        var current = ""
        var quoteState: QuoteState?
        var isEscaping = false
        var tokenStarted = false

        func finishToken() {
            guard tokenStarted || !current.isEmpty else { return }
            args.append(current)
            current = ""
            tokenStarted = false
        }

        for ch in s {
            if isEscaping {
                current.append(ch)
                isEscaping = false
                tokenStarted = true
                continue
            }

            switch ch {
            case "\\":
                if quoteState == .single {
                    current.append(ch)
                } else {
                    isEscaping = true
                }
                tokenStarted = true
            case "\"":
                if quoteState == .single {
                    current.append(ch)
                } else if quoteState == .double {
                    quoteState = nil
                } else {
                    quoteState = .double
                }
                tokenStarted = true
            case "'":
                if quoteState == .double {
                    current.append(ch)
                } else if quoteState == .single {
                    quoteState = nil
                } else {
                    quoteState = .single
                }
                tokenStarted = true
            default:
                if ch.isWhitespace && quoteState == nil {
                    finishToken()
                    continue
                }
                current.append(ch)
                tokenStarted = true
            }
        }

        if isEscaping {
            throw ArgumentParsingError.danglingEscape
        }

        switch quoteState {
        case .single?:
            throw ArgumentParsingError.unterminatedSingleQuote
        case .double?:
            throw ArgumentParsingError.unterminatedDoubleQuote
        case nil:
            break
        }

        finishToken()
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
