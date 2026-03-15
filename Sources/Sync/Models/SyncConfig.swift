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
}
