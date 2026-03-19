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

    private enum IconState: String, CaseIterable {
        case idle = "SyncIdle"
        case active = "SyncActive"
        case problem = "SyncProblem"
    }

    private static let icons: [IconState: NSImage] = {
        let size = NSSize(width: 18, height: 18)
        var result: [IconState: NSImage] = [:]
        for state in IconState.allCases {
            guard let path = Bundle.main.path(forResource: "\(state.rawValue)@2x", ofType: "png"),
                  let img = NSImage(contentsOfFile: path) else { continue }
            img.size = size
            img.isTemplate = true
            result[state] = img
        }
        return result
    }()

    var body: some View {
        let state: IconState = if manager.syncStates.values.contains(where: \.isRunning) {
            .active
        } else if store.configs.contains(where: { $0.lastSyncSuccess == false }) {
            .problem
        } else {
            .idle
        }
        if let icon = Self.icons[state] {
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
