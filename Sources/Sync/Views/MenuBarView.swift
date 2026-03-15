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
            Text("Sync now")
                .foregroundStyle(.secondary)
            ForEach(store.configs) { config in
                let state = manager.state(for: config.id)
                Button {
                    manager.syncNow(id: config.id)
                } label: {
                    HStack(spacing: 6) {
                        Text(config.name)
                        Spacer()
                        Image(systemName: statusIcon(running: state.isRunning, success: config.lastSyncSuccess))
                            .foregroundStyle(statusColor(running: state.isRunning, success: config.lastSyncSuccess).opacity(0.6))
                            .font(.caption2)
                    }
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

    private func statusText(running: Bool, lastSync: Date?) -> String {
        if running { return "syncing..." }
        guard let date = lastSync else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
