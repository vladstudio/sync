import Foundation

enum RemoteIcon {
    static func sfSymbol(for type: String) -> String {
        switch type {
        // Local & virtual
        case "local": "internaldrive"
        case "alias": "link"
        case "memory": "memorychip"

        // Meta remotes
        case "crypt": "lock.fill"
        case "compress": "doc.zipper"
        case "chunker": "scissors"
        case "combine", "union": "square.stack.3d.up.fill"
        case "hasher": "number"
        case "archive": "archivebox.fill"

        // Network protocols
        case "sftp": "terminal.fill"
        case "ftp": "network"
        case "http", "webdav": "globe"
        case "smb": "server.rack"
        case "hdfs": "server.rack"

        // Google
        case "drive": "externaldrive.fill"
        case "gcs": "externaldrive.badge.icloud"
        case "gphotos": "photo.on.rectangle.angled"

        // Microsoft
        case "onedrive": "cloud.fill"
        case "azureblob", "azurefiles": "cloud.fill"

        // Apple
        case "iclouddrive": "icloud"

        // Privacy-focused
        case "protondrive": "lock.shield.fill"

        // Brands with fitting symbols
        case "dropbox": "drop.fill"
        case "box", "filefabric": "shippingbox.fill"
        case "mega": "m.circle.fill"
        case "mailru": "envelope.fill"
        case "b2": "b.circle.fill"
        case "s3": "s.circle.fill"
        case "pcloud", "pikpak": "p.circle.fill"

        // Object storage
        case "swift", "oracleobjectstorage", "qingstor", "storj": "cloud.fill"

        // File hosting / sharing
        case "fichier", "gofile", "linkbox", "pixeldrain",
             "premiumizeme", "putio", "ulozto", "filelu",
             "filescom", "filen", "internxt": "doc.fill"

        // Cloud drives / sync services
        case "hidrive", "opendrive", "drime": "externaldrive.fill"
        case "seafile", "jottacloud", "koofr", "sugarsync",
             "yandex", "zoho", "quatrix", "sharefile",
             "internetarchive", "sia", "shade", "netstorage",
             "cloudinary": "cloud.fill"

        default: "cloud.fill"
        }
    }
}
