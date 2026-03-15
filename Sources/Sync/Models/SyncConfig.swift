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

enum Schedule: Codable, Sendable, Equatable {
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

struct SyncConfig: Codable, Identifiable, Sendable, Equatable {
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
    var bandwidthLimit: String? = nil
    var excludePatterns: [String] = [".DS_Store"]
    var extraFlags: String = ""
    var lastSyncDate: Date? = nil
    var lastSyncSuccess: Bool? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        localPath = try c.decode(String.self, forKey: .localPath)
        remote = try c.decode(String.self, forKey: .remote)
        remoteType = try c.decodeIfPresent(String.self, forKey: .remoteType) ?? ""
        remotePath = try c.decode(String.self, forKey: .remotePath)
        direction = try c.decode(Direction.self, forKey: .direction)
        schedule = try c.decode(Schedule.self, forKey: .schedule)
        mode = try c.decode(SyncMode.self, forKey: .mode)
        keepDeletedFiles = try c.decode(Bool.self, forKey: .keepDeletedFiles)
        bandwidthLimit = try c.decodeIfPresent(String.self, forKey: .bandwidthLimit)
        excludePatterns = try c.decode([String].self, forKey: .excludePatterns)
        extraFlags = try c.decode(String.self, forKey: .extraFlags)
        lastSyncDate = try c.decodeIfPresent(Date.self, forKey: .lastSyncDate)
        lastSyncSuccess = try c.decodeIfPresent(Bool.self, forKey: .lastSyncSuccess)
    }
}
