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
    var bandwidthLimit: String? = nil
    var excludePatterns: [String] = [".DS_Store"]
    var extraFlags: String = ""
    var lastSyncDate: Date? = nil
    var lastSyncSuccess: Bool? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        localPath = try c.decodeIfPresent(String.self, forKey: .localPath) ?? ""
        remote = try c.decodeIfPresent(String.self, forKey: .remote) ?? ""
        remoteType = try c.decodeIfPresent(String.self, forKey: .remoteType) ?? ""
        remotePath = try c.decodeIfPresent(String.self, forKey: .remotePath) ?? ""
        direction = try c.decodeIfPresent(Direction.self, forKey: .direction) ?? .localToRemote
        schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule) ?? .manual
        mode = try c.decodeIfPresent(SyncMode.self, forKey: .mode) ?? .copy
        keepDeletedFiles = try c.decodeIfPresent(Bool.self, forKey: .keepDeletedFiles) ?? true
        bandwidthLimit = try c.decodeIfPresent(String.self, forKey: .bandwidthLimit)
        excludePatterns = try c.decodeIfPresent([String].self, forKey: .excludePatterns) ?? [".DS_Store"]
        extraFlags = try c.decodeIfPresent(String.self, forKey: .extraFlags) ?? ""
        lastSyncDate = try c.decodeIfPresent(Date.self, forKey: .lastSyncDate)
        lastSyncSuccess = try c.decodeIfPresent(Bool.self, forKey: .lastSyncSuccess)
    }
}
