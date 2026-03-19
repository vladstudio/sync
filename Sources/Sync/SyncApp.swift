import SwiftUI

@MainActor
enum WindowTracker {
    private static var count = 0

    static func opened() {
        count += 1
        NSApp.setActivationPolicy(.regular)
    }

    static func closed() {
        count = max(0, count - 1)
        if count == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var manager: SyncManager
    @ObservedObject var store: ConfigStore

    private static let icons: [String: NSImage] = {
        let size = NSSize(width: 18, height: 18)
        var result: [String: NSImage] = [:]
        for name in ["SyncIdle", "SyncActive", "SyncProblem"] {
            guard let path = Bundle.main.path(forResource: "\(name)@2x", ofType: "png"),
                  let img = NSImage(contentsOfFile: path) else { continue }
            img.size = size
            img.isTemplate = true
            result[name] = img
        }
        return result
    }()

    var body: some View {
        let icon: NSImage? = if manager.syncStates.values.contains(where: \.isRunning) {
            Self.icons["SyncActive"]
        } else if store.configs.contains(where: { $0.lastSyncSuccess == false }) {
            Self.icons["SyncProblem"]
        } else {
            Self.icons["SyncIdle"]
        }
        if let icon {
            Image(nsImage: icon)
        }
    }
}

@main
struct SyncApp: App {
    @StateObject private var store: ConfigStore
    @StateObject private var manager: SyncManager

    init() {
        let s = ConfigStore()
        s.load()
        let m = SyncManager(store: s)
        m.startAllOnce()
        _store = StateObject(wrappedValue: s)
        _manager = StateObject(wrappedValue: m)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store, manager: manager)
        } label: {
            MenuBarLabel(manager: manager, store: store)
        }

        Window("Manage Syncs", id: "manage") {
            ManageSyncsView(store: store, manager: manager)
        }
        .windowStyle(.hiddenTitleBar)

        Window("Settings", id: "settings") {
            SettingsView(store: store)
        }
        .windowResizability(.contentSize)
    }
}
