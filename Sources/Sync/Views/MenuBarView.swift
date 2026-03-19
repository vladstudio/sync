import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var manager: SyncManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.configs.isEmpty {
            Text("No syncs configured")
                .foregroundStyle(.secondary)
        } else {
            ForEach(store.configs) { config in
                let state = manager.state(for: config.id)
                Button {
                    manager.pendingSelection = config.id
                    openWindow(id: "manage")
                    NSApp.activate()
                } label: {
                    Text(config.name + "\t") + Text(Image(systemName: SyncStatusDisplay.icon(running: state.isRunning, success: config.lastSyncSuccess)))
                        .foregroundColor(SyncStatusDisplay.color(running: state.isRunning, success: config.lastSyncSuccess).opacity(0.6))
                        .font(.caption2)
                }
            }
        }

        Divider()

        Button("Add Sync") {
            manager.pendingSelection = ManageSyncsView.addSyncID
            openWindow(id: "manage")
            NSApp.activate()
        }

        Button("Settings") {
            openWindow(id: "settings")
            NSApp.activate()
        }

        Button("About Sync") {
            NSWorkspace.shared.open(URL(string: "https://sync.vlad.studio")!)
        }

        Divider()

        Button("Quit") {
            manager.stopAll()
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }

}

enum SyncStatusDisplay {
    static func icon(running: Bool, success: Bool?) -> String {
        if running { return "arrow.triangle.2.circlepath" }
        switch success {
        case true: return "checkmark.circle.fill"
        case false: return "xmark.circle.fill"
        default: return "circle.dotted"
        }
    }

    static func color(running: Bool, success: Bool?) -> Color {
        if running { return .secondary }
        switch success {
        case true: return .green
        case false: return .red
        default: return .secondary
        }
    }
}
