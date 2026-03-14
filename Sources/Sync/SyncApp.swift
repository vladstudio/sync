import SwiftUI
import AppKit

@main
struct SyncApp: App {
    @StateObject private var store: ConfigStore
    @StateObject private var manager: SyncManager

    init() {
        let s = ConfigStore()
        s.load()
        _store = StateObject(wrappedValue: s)
        _manager = StateObject(wrappedValue: SyncManager(store: s))

        // Register menubar icon as template image from bundle resources
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.setName("MenuBarIcon")
        }
    }

    var body: some Scene {
        MenuBarExtra("Sync", image: "MenuBarIcon") {
            MenuBarView(store: store, manager: manager)
        }

        Window("Manage Syncs", id: "manage") {
            ManageSyncsView(store: store, manager: manager)
                .frame(minWidth: 600, minHeight: 400)
        }

        Window("Settings", id: "settings") {
            SettingsView(store: store)
                .frame(width: 400, height: 120)
        }
    }
}
