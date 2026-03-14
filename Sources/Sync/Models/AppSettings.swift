import Foundation

struct AppSettings: Codable, Sendable {
    var rclonePath: String
    var startOnLogin: Bool

    init(rclonePath: String = "/opt/homebrew/bin/rclone", startOnLogin: Bool = false) {
        self.rclonePath = rclonePath
        self.startOnLogin = startOnLogin
    }
}
