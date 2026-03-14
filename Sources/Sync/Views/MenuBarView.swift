import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var manager: SyncManager
    @Environment(\.openWindow) private var openWindow
    @State private var startOnLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Start on Login", isOn: $startOnLogin)
            .onChange(of: startOnLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    store.settings.startOnLogin = newValue
                    store.saveSettings()
                } catch {
                    startOnLogin = !newValue
                }
            }

        Divider()

        if store.configs.isEmpty {
            Text("No syncs configured")
                .foregroundStyle(.secondary)
        } else {
            ForEach(store.configs) { config in
                let state = manager.state(for: config.id)
                Button {
                    if state.isRunning {
                        openWindow(id: "manage")
                    } else {
                        manager.syncNow(id: config.id)
                    }
                } label: {
                    HStack {
                        Text(config.name)
                        Spacer()
                        if state.isRunning {
                            Text("syncing...")
                                .foregroundStyle(.secondary)
                        } else if let date = config.lastSyncDate {
                            Text(date, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        Divider()

        Button("Manage Syncs") {
            openWindow(id: "manage")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Settings") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit") {
            manager.stopAll()
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }
}
