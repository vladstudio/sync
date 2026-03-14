import Foundation

struct AppSettings: Codable, Sendable {
    var rclonePath: String = "/opt/homebrew/bin/rclone"
    var startOnLogin: Bool = false
}
