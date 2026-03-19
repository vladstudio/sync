import SwiftUI

struct ManageSyncsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var manager: SyncManager
    @State private var selection: UUID?
    @State private var draftConfig = SyncConfig()
    @State private var deletingConfig: SyncConfig?
    @State private var logInfo: LogInfo?

    private static let addSyncID = UUID()
    private let sidebarWidth: CGFloat = 240
    private let headerHeight: CGFloat = 64

    private struct LogInfo {
        let configId: UUID
        let title: String
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 450)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator(configure: ManageSyncsView.configureWindow))
        .onAppear {
            WindowTracker.opened()
            if let pending = manager.pendingSelection {
                selection = pending
                manager.pendingSelection = nil
            } else if selection == nil {
                selection = store.configs.first?.id ?? Self.addSyncID
            }
        }
        .onDisappear { WindowTracker.closed() }
        .onChange(of: manager.pendingSelection) { _, newValue in
            if let id = newValue {
                selection = id
                logInfo = nil
                manager.pendingSelection = nil
            }
        }
        .onChange(of: selection) { _, newValue in
            logInfo = nil
            if newValue == Self.addSyncID {
                draftConfig = SyncConfig()
            }
        }
        .alert("Delete Sync?", isPresented: Binding(
            get: { deletingConfig != nil },
            set: { if !$0 { deletingConfig = nil } }
        )) {
            Button("Cancel", role: .cancel) { deletingConfig = nil }
            Button("Delete", role: .destructive) {
                if let config = deletingConfig {
                    manager.cancelSync(id: config.id)
                    manager.teardownSchedule(for: config.id)
                    manager.cleanupState(for: config.id)
                    manager.deletePersistedLog(id: config.id)
                    if selection == config.id { selection = nil }
                    store.deleteConfig(id: config.id)
                }
                deletingConfig = nil
            }
        } message: {
            if let config = deletingConfig {
                Text("Are you sure you want to delete \"\(config.name)\"?")
            }
        }
        .alert("Error", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader
            List(selection: $selection) {
                addSyncRow

                ForEach(store.configs) { config in
                    syncRow(config)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sidebarHeader: some View {
        HStack {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .frame(height: headerHeight, alignment: .bottom)
        .background(.background)
    }

    private var addSyncRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Sync")
                Text("Create a new sync configuration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .tag(Self.addSyncID)
    }

    private func syncRow(_ config: SyncConfig) -> some View {
        let state = manager.state(for: config.id)
        return HStack(spacing: 8) {
            RemoteIcon.icon(for: config.remoteType)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                Text("\(config.direction.label) · \(config.schedule.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.isRunning {
                ProgressView().controlSize(.small)
            } else if let success = config.lastSyncSuccess {
                Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(success ? .green : .orange)
                    .font(.caption)
                    .help(success ? "Last sync succeeded" : "Last sync failed")
            }
        }
        .tag(config.id)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            detailBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func editDetail(id: UUID, config: SyncConfig) -> some View {
        EditSyncView(store: store, manager: manager, config: config, onDelete: {
            deletingConfig = config
        }) { updated in
            var updated = updated
            let previous = store.configs.first(where: { $0.id == updated.id })
            if previous?.lastSyncSuccess == false && !manager.state(for: updated.id).isRunning {
                updated.lastSyncSuccess = nil
                updated.lastSyncError = nil
            }
            store.updateConfig(updated)
            if let previous, scheduleInputChanged(from: previous, to: updated) {
                manager.teardownSchedule(for: updated.id)
                manager.setupSchedule(for: updated)
            }
        }
        .id(id)
    }

    private var createDetail: some View {
        EditSyncView(store: store, manager: manager, config: draftConfig) { config in
            draftConfig = config
        }
        .id(draftConfig.id)
    }

    private func logDetail(_ info: LogInfo) -> some View {
        LogView(configId: info.configId, manager: manager)
    }

    @ViewBuilder
    private var detailHeader: some View {
        if let info = logInfo {
            headerBar {
                Text(info.title)
                    .font(.headline)
                Spacer()
                if manager.state(for: info.configId).isRunning {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { manager.cancelSync(id: info.configId) }
                }
                Button("Close") { logInfo = nil }
            }
        } else if selection == Self.addSyncID {
            headerBar {
                Text("Create Sync")
                    .font(.headline)
                Spacer()
                Button("Dry Run") {
                    manager.dryRun(config: draftConfig)
                    let name = draftConfig.name.isEmpty ? "Untitled" : draftConfig.name
                    logInfo = LogInfo(configId: draftConfig.id, title: "Dry Run: \(name)")
                }
                .disabled(!isConfigValid(draftConfig))
                Button("Cancel") {
                    draftConfig = SyncConfig()
                    if let first = store.configs.first {
                        selection = first.id
                    }
                }
                Button("Save") {
                    store.addConfig(draftConfig)
                    manager.setupSchedule(for: draftConfig)
                    selection = draftConfig.id
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isConfigValid(draftConfig))
            }
        } else if let id = selection, let config = store.configs.first(where: { $0.id == id }) {
            headerBar {
                Text(config.name.isEmpty ? "Untitled" : config.name)
                    .font(.headline)
                Spacer()
                Button("Dry Run") {
                    manager.dryRun(config: config)
                    logInfo = LogInfo(configId: id, title: "Dry Run: \(config.name)")
                }
                .disabled(!isConfigValid(config))
                if config.lastSyncSuccess == false {
                    Button("Retry") {
                        manager.syncNow(id: id)
                    }
                    .disabled(manager.state(for: id).isRunning)
                    Button("Sync Now with --force") {
                        manager.syncNow(id: id, force: true)
                    }
                    .disabled(manager.state(for: id).isRunning)
                } else {
                    Button("Sync Now") {
                        manager.syncNow(id: id)
                    }
                    .disabled(manager.state(for: id).isRunning)
                }
                Button("Log") {
                    logInfo = LogInfo(configId: id, title: "Log: \(config.name)")
                }
            }
        } else {
            headerBar {
                Text("Manage Syncs")
                    .font(.headline)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var detailBody: some View {
        if let info = logInfo {
            logDetail(info)
        } else if selection == Self.addSyncID {
            createDetail
        } else if let id = selection, let config = store.configs.first(where: { $0.id == id }) {
            editDetail(id: id, config: config)
        } else {
            Text("Select a sync or add a new one")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func headerBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10, content: content)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .frame(height: headerHeight, alignment: .bottom)
            .background(.background)
    }

    private static func configureWindow(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
    }

    private func isConfigValid(_ config: SyncConfig) -> Bool {
        !config.name.isEmpty && !config.localPath.isEmpty && !config.remote.isEmpty
    }

    private func scheduleInputChanged(from old: SyncConfig, to new: SyncConfig) -> Bool {
        old.schedule != new.schedule ||
        old.direction != new.direction ||
        old.localPath != new.localPath
    }
}
