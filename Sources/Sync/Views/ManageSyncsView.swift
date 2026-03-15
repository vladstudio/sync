import SwiftUI

struct ManageSyncsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var manager: SyncManager
    @State private var selection: UUID?
    @State private var draftConfig = SyncConfig()
    @State private var deletingConfig: SyncConfig?
    @State private var logInfo: LogInfo?

    private static let addSyncID = UUID()

    private struct LogInfo {
        let configId: UUID
        let title: String
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 450)
        .onAppear {
            WindowTracker.opened()
            if selection == nil, let first = store.configs.first {
                selection = first.id
            }
        }
        .onDisappear { WindowTracker.closed() }
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

    private var sidebar: some View {
        List(selection: $selection) {
            Label("Add Sync", systemImage: "plus")
                .tag(Self.addSyncID)
            ForEach(store.configs) { config in
                let state = manager.state(for: config.id)
                HStack(spacing: 8) {
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
                        Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(success ? .green : .red)
                            .font(.caption)
                    }
                }
                .tag(config.id)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        if let logInfo {
            logDetail(logInfo)
        } else if selection == Self.addSyncID {
            createDetail
        } else if let id = selection, let config = store.configs.first(where: { $0.id == id }) {
            editDetail(id: id, config: config)
        } else {
            Text("Select a sync or add a new one")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Edit existing sync

    private func editDetail(id: UUID, config: SyncConfig) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(config.name.isEmpty ? "Untitled" : config.name)
                    .font(.headline)
                Spacer()
                Button("Dry Run") {
                    manager.dryRun(config: config)
                    logInfo = LogInfo(configId: id, title: "Dry Run: \(config.name)")
                }
                Button("Sync Now") {
                    manager.syncNow(id: id)
                }
                .disabled(manager.state(for: id).isRunning)
                Button("Log") {
                    logInfo = LogInfo(configId: id, title: "Log: \(config.name)")
                }
            }
            .padding()
            .layoutPriority(1)

            EditSyncView(store: store, manager: manager, config: config, onDelete: {
                deletingConfig = config
            }) { updated in
                store.updateConfig(updated)
                manager.teardownSchedule(for: updated.id)
                manager.setupSchedule(for: updated)
            }
            .id(id)
        }
    }

    // MARK: - Create new sync

    private var createDetail: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create Sync")
                    .font(.headline)
                Spacer()
                Button("Dry Run") {
                    manager.dryRun(config: draftConfig)
                    let name = draftConfig.name.isEmpty ? "Untitled" : draftConfig.name
                    logInfo = LogInfo(configId: draftConfig.id, title: "Dry Run: \(name)")
                }
                Button("Cancel") {
                    selection = store.configs.first?.id
                }
                Button("Save") {
                    store.addConfig(draftConfig)
                    manager.setupSchedule(for: draftConfig)
                    selection = draftConfig.id
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftConfig.name.isEmpty || draftConfig.localPath.isEmpty || draftConfig.remote.isEmpty)
            }
            .padding()
            .layoutPriority(1)

            EditSyncView(store: store, manager: manager, config: draftConfig) { config in
                draftConfig = config
            }
        }
    }

    // MARK: - Log / Dry Run

    private func logDetail(_ info: LogInfo) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(info.title)
                    .font(.headline)
                Spacer()
                if manager.state(for: info.configId).isRunning {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { manager.cancelSync(id: info.configId) }
                }
                Button("Close") { logInfo = nil }
            }
            .padding()
            .layoutPriority(1)

            LogView(configId: info.configId, manager: manager)
        }
    }
}
