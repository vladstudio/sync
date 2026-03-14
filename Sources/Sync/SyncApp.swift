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
        let resourcesPath = Bundle.main.bundlePath + "/Contents/Resources/MenuBarIcon.png"
        if let image = NSImage(contentsOfFile: resourcesPath) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.setName("SyncMenuBarIcon")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store, manager: manager)
                .onAppear { manager.startAllOnce() }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }

        Window("Manage Syncs", id: "manage") {
            ManageSyncsView(store: store, manager: manager)
                .frame(minWidth: 600, minHeight: 400)
        }

        Window("Settings", id: "settings") {
            SettingsView(store: store)
        }
        .windowResizability(.contentSize)
    }
}
