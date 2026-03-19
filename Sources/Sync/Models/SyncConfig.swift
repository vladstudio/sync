import Foundation

enum Direction: String, Codable, CaseIterable, Sendable {
    case remoteToLocal
    case localToRemote
    case bidirectional

    var label: String {
        switch self {
        case .remoteToLocal: "Remote → Local"
        case .localToRemote: "Local → Remote"
        case .bidirectional: "Bidirectional"
        }
    }
}

enum Schedule: Codable, Sendable, Equatable, Hashable {
    case manual
    case interval(minutes: Int)
    case onLocalChange

    var label: String {
        switch self {
        case .manual: "Manual"
        case .interval(let m): "Every \(m) min"
        case .onLocalChange: "On local change"
        }
    }
}

enum SyncMode: String, Codable, CaseIterable, Sendable {
    case sync
    case copy

    var label: String {
        switch self {
        case .sync: "Sync (mirror, deletes)"
        case .copy: "Copy (additive only)"
        }
    }
}

struct SyncConfig: Codable, Identifiable, Sendable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var localPath: String = ""
    var remote: String = ""
    var remoteType: String = ""
    var remotePath: String = ""
    var direction: Direction = .localToRemote
    var schedule: Schedule = .manual
    var mode: SyncMode = .copy
    var keepDeletedFiles: Bool = true
    var bandwidthLimit: String?
    var excludePatterns: [String] = [".DS_Store"]
    var useChecksum: Bool = false
    var ignoreExisting: Bool = false
    var transfers: Int?
    var checkers: Int?
    var extraFlags: String = ""
    var lastSyncDate: Date?
    var lastSyncSuccess: Bool?
    var lastSyncError: String?

    var remoteFull: String { "\(remote):\(remotePath)" }
    var remoteBackupPath: String { "\(remote):.rclone-backup/\(id.uuidString)" }

    init() {}

    init(from decoder: Decoder) throws {
        let d = SyncConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? d.id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        localPath = try c.decodeIfPresent(String.self, forKey: .localPath) ?? d.localPath
        remote = try c.decodeIfPresent(String.self, forKey: .remote) ?? d.remote
        remoteType = try c.decodeIfPresent(String.self, forKey: .remoteType) ?? d.remoteType
        remotePath = try c.decodeIfPresent(String.self, forKey: .remotePath) ?? d.remotePath
        direction = try c.decodeIfPresent(Direction.self, forKey: .direction) ?? d.direction
        schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule) ?? d.schedule
        mode = try c.decodeIfPresent(SyncMode.self, forKey: .mode) ?? d.mode
        keepDeletedFiles = try c.decodeIfPresent(Bool.self, forKey: .keepDeletedFiles) ?? d.keepDeletedFiles
        bandwidthLimit = try c.decodeIfPresent(String.self, forKey: .bandwidthLimit) ?? d.bandwidthLimit
        excludePatterns = try c.decodeIfPresent([String].self, forKey: .excludePatterns) ?? d.excludePatterns
        useChecksum = try c.decodeIfPresent(Bool.self, forKey: .useChecksum) ?? d.useChecksum
        ignoreExisting = try c.decodeIfPresent(Bool.self, forKey: .ignoreExisting) ?? d.ignoreExisting
        transfers = try c.decodeIfPresent(Int.self, forKey: .transfers) ?? d.transfers
        checkers = try c.decodeIfPresent(Int.self, forKey: .checkers) ?? d.checkers
        extraFlags = try c.decodeIfPresent(String.self, forKey: .extraFlags) ?? d.extraFlags
        lastSyncDate = try c.decodeIfPresent(Date.self, forKey: .lastSyncDate) ?? d.lastSyncDate
        lastSyncSuccess = try c.decodeIfPresent(Bool.self, forKey: .lastSyncSuccess) ?? d.lastSyncSuccess
        lastSyncError = try c.decodeIfPresent(String.self, forKey: .lastSyncError) ?? d.lastSyncError
    }
}
