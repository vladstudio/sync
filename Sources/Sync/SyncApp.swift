import SwiftUI

@MainActor
enum WindowTracker {
    private static var count = 0

    static func opened() {
        count += 1
        NSApp.setActivationPolicy(.regular)
    }

    static func closed() {
        count -= 1
        if count <= 0 {
            count = 0
            NSApp.setActivationPolicy(.accessory)
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
            Image(systemName: "arrow.up.arrow.down")
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
