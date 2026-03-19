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
            Text("Sync now")
                .foregroundStyle(.secondary)
            ForEach(store.configs) { config in
                let state = manager.state(for: config.id)
                Button {
                    manager.syncNow(id: config.id)
                } label: {
                    Text(config.name + "\t") + Text(Image(systemName: statusIcon(running: state.isRunning, success: config.lastSyncSuccess)))
                        .foregroundColor(statusColor(running: state.isRunning, success: config.lastSyncSuccess).opacity(0.6))
                        .font(.caption2)
                }
                .disabled(state.isRunning)
            }
        }

        Divider()

        Button("Manage Syncs") {
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

    private func statusIcon(running: Bool, success: Bool?) -> String {
        if running { return "arrow.triangle.2.circlepath" }
        switch success {
        case true: return "checkmark.circle.fill"
        case false: return "xmark.circle.fill"
        default: return "circle.dotted"
        }
    }

    private func statusColor(running: Bool, success: Bool?) -> Color {
        if running { return .secondary }
        switch success {
        case true: return .green
        case false: return .red
        default: return .secondary
        }
    }

}
