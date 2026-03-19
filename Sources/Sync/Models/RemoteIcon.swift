import SwiftUI

@MainActor
enum RemoteIcon {
    /// Types that have brand SVG icons bundled as resources.
    private static let brandTypes: Set<String> = [
        "drive", "gcs", "gphotos", "dropbox", "b2", "box",
        "iclouddrive", "protondrive", "mega", "netstorage",
        "seafile", "zoho", "internetarchive", "cloudinary",
        "sharefile", "swift", "filen", "filescom", "hdfs",
        "yandex", "mailru",
    ]

    private static var cache: [String: NSImage] = [:]

    /// Returns a SwiftUI view for the given rclone remote type.
    static func icon(for type: String, size: CGFloat = 16) -> some View {
        image(for: type)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    private static func image(for type: String) -> Image {
        if brandTypes.contains(type), let nsImage = loadSVG(for: type) {
            Image(nsImage: nsImage)
        } else {
            Image(systemName: sfSymbol(for: type))
        }
    }

    private static func loadSVG(for type: String) -> NSImage? {
        if let cached = cache[type] { return cached }
        guard let url = Bundle.module.url(
            forResource: "remote-\(type)",
            withExtension: "svg",
            subdirectory: "RemoteIcons"
        ) else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache[type] = image
        return image
    }

    private static func sfSymbol(for type: String) -> String {
        switch type {
        case "local": "internaldrive"
        case "alias": "link"
        case "memory": "memorychip"
        case "crypt": "lock.fill"
        case "compress": "doc.zipper"
        case "chunker": "scissors"
        case "combine", "union": "square.stack.3d.up.fill"
        case "hasher": "number"
        case "archive": "archivebox.fill"
        case "sftp": "terminal.fill"
        case "ftp": "network"
        case "http", "webdav": "globe"
        case "smb": "server.rack"
        case "onedrive": "cloud.fill"
        case "azureblob", "azurefiles": "cloud.fill"
        case "s3": "cloud.fill"
        default: "cloud.fill"
        }
    }
}
