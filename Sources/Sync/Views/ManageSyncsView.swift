import SwiftUI

struct ManageSyncsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var manager: SyncManager
    @State private var selection: UUID?
    @State private var draftConfig = SyncConfig()
    @State private var editDrafts: [UUID: SyncConfig] = [:]
    @State private var editResetTokens: [UUID: Int] = [:]
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
                    editDrafts.removeValue(forKey: config.id)
                    editResetTokens.removeValue(forKey: config.id)
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
                        Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(success ? .green : .orange)
                            .font(.caption)
                            .help(success ? "Last sync succeeded" : "Last sync failed")
                    }
                }
                .tag(config.id)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail

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

    private func editDetail(id: UUID, config: SyncConfig) -> some View {
        let draft = editDrafts[id] ?? config
        let hasChanges = draft != config

        return EditSyncView(store: store, manager: manager, config: draft, onDelete: {
            deletingConfig = config
        }) { updated in
            editDrafts[id] = updated
        }
        .id("\(id.uuidString)-\(editResetTokens[id, default: 0])")
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text(draft.name.isEmpty ? "Untitled" : draft.name)
                        .font(.headline)
                    Spacer()
                    Button("Dry Run") {
                        manager.dryRun(config: draft)
                        logInfo = LogInfo(configId: id, title: "Dry Run: \(draft.name)")
                    }
                    Button("Sync Now") {
                        manager.syncNow(id: id)
                    }
                    .disabled(manager.state(for: id).isRunning)
                    Button("Log") {
                        logInfo = LogInfo(configId: id, title: "Log: \(draft.name)")
                    }
                    Button("Revert") {
                        editDrafts.removeValue(forKey: id)
                        editResetTokens[id, default: 0] += 1
                    }
                    .disabled(!hasChanges)
                    Button("Save") {
                        store.updateConfig(draft)
                        if scheduleInputChanged(from: config, to: draft) {
                            manager.teardownSchedule(for: id)
                            manager.setupSchedule(for: draft)
                        }
                        editDrafts.removeValue(forKey: id)
                        editResetTokens[id, default: 0] += 1
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || !isConfigValid(draft))
                }
                .padding()
                Divider()
            }
            .background(.background)
        }
    }

    private var createDetail: some View {
        EditSyncView(store: store, manager: manager, config: draftConfig) { config in
            draftConfig = config
        }
        .safeAreaInset(edge: .top, spacing: 0) {
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
                    .disabled(!isConfigValid(draftConfig))
                }
                .padding()
                Divider()
            }
            .background(.background)
        }
    }

    private func logDetail(_ info: LogInfo) -> some View {
        LogView(configId: info.configId, manager: manager)
            .safeAreaInset(edge: .top, spacing: 0) {
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
                    Divider()
                }
                .background(.background)
            }
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
